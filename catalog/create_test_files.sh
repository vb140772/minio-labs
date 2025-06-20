#!/bin/bash

# Function to check catalog support
check_catalog_support() {
    local alias=$1
    if ! mc batch generate "$alias/" list 2>&1 | grep -q "catalog"
    then
        echo "Error: Catalog is not supported on this cluster"
        exit 1
    fi
    echo "Catalog is supported on this cluster"
}

# Function to generate random string of specified length
generate_random_name() {
    local length=${1:-10}
    openssl rand -hex $((length/2+1)) | cut -c1-$length
}

# Function to generate random data of specified size
generate_random_data() {
    local size=$1
    openssl rand -out "$2" $size
}

# Function to check if jq is installed
check_jq() {
    if ! command -v jq &> /dev/null
    then
        echo "Error: jq is required but not installed. Please install jq first."
        exit 1
    fi
}

# Function to check if openssl is installed
check_openssl() {
    if ! command -v openssl &> /dev/null
    then
        echo "Error: openssl is required but not installed. Please install openssl first."
        exit 1
    fi
}

# Function to read MinIO configuration from mc config
get_alias_config() {
    local alias=$1
    local config_file="$HOME/.mc/config.json"
    
    if [ ! -f "$config_file" ]
    then
        echo "Error: MC config file not found at $config_file" >&2
        exit 1
    fi
    
    # Check if alias exists in config
    if ! jq -e ".aliases.\"$alias\"" "$config_file" > /dev/null 2>&1
    then
        echo "Error: Alias '$alias' not found in mc config." >&2
        echo "Available aliases: $(jq -r '.aliases | keys | join(", ")' "$config_file")" >&2
        exit 1
    fi
}

# Function to cleanup catalog files and buckets
cleanup_catalog_resources() {
    local alias=$1
    local bucket=$2
    
    echo "Cleaning up catalog resources..."
    
    # Remove catalog YAML files
    if [ -f "catalog.yaml" ]; then
        rm -f "catalog.yaml"
        echo "Removed catalog.yaml"
    fi
    
    if [ -f "catalog_with_filter.yaml" ]; then
        rm -f "catalog_with_filter.yaml"
        echo "Removed catalog_with_filter.yaml"
    fi
    
    # Remove catalog bucket
    if mc ls "$alias/catalog" &> /dev/null; then
        mc rb --force "$alias/catalog" &> /dev/null
        echo "Removed catalog bucket"
    fi
    
    # Remove test bucket if it exists
    if mc ls "$alias/$bucket" &> /dev/null; then
        mc rb --force "$alias/$bucket" &> /dev/null
        echo "Removed test bucket: $bucket"
    fi
    
    echo "Cleanup completed"
}

# Function to create catalog configuration file
create_catalog_config() {
    local config_file=$1
    local bucket=$2
    local catalog_bucket=$3
    local size_filter=$4
    local format=${5:-CSV}
    
    echo "Creating catalog configuration..."
    cat > "$config_file" << EOF
catalog:
  apiVersion: v1
  bucket: $bucket

  destination:
    bucket: $catalog_bucket
    format: $format
    compression: off

  name:
    - match: "*"

  versions: current
EOF

    # Add size filter if provided
    if [ -n "$size_filter" ]; then
        echo "  filters:" >> "$config_file"
        echo "    size:" >> "$config_file"
        echo "      equalTo: $size_filter" >> "$config_file"
        echo "Catalog configuration with size filter created"
    else
        echo "Catalog configuration created"
    fi
}

# Function to start and monitor catalog job
run_catalog_job() {
    local alias=$1
    local config_file=$2
    local job_description=$3
    
    echo "Starting $job_description..."
    # Start the catalog job and capture the job ID
    BATCH_OUTPUT=$(mc batch start "$alias/" "$config_file")
    echo "$BATCH_OUTPUT"
    
    # Extract the job ID using regex
    if [[ $BATCH_OUTPUT =~ \`([^\']+)\` ]]; then
        JOB_ID="${BASH_REMATCH[1]}"
        echo "Monitoring $job_description: $JOB_ID"
        
        # Monitor job status until complete or error
        while true; do
            # Get detailed status in JSON format
            STATUS_JSON=$(mc batch status "$alias/" "$JOB_ID" --json)
            
            # Extract relevant fields
            COMPLETE=$(echo "$STATUS_JSON" | jq -r '.metric.complete')
            FAILED=$(echo "$STATUS_JSON" | jq -r '.metric.failed')
            OBJECTS_SCANNED=$(echo "$STATUS_JSON" | jq -r '.metric.catalog.objectsScannedCount // 0')
            OBJECTS_MATCHED=$(echo "$STATUS_JSON" | jq -r '.metric.catalog.objectsMatchedCount // 0')
            ERROR_MSG=$(echo "$STATUS_JSON" | jq -r '.metric.catalog.errorMsg // ""')
            
            # Show progress
            echo -ne "\rWaiting for $job_description to complete..."
            
            # Check completion status
            if [ "$COMPLETE" = "true" ]; then
                if [ "$FAILED" = "true" ]; then
                    echo -e "\n$job_description failed: $ERROR_MSG"
                    return 1
                else
                    echo -e "\n$job_description completed successfully"
                    # Extract CSV file path from manifest location
                    MANIFEST_PATH=$(echo "$STATUS_JSON" | jq -r '.metric.catalog.manifestPathObject // ""')
                    if [ -n "$MANIFEST_PATH" ]; then
                        # Get the full path to CSV files directory
                        CSV_DIR="${MANIFEST_PATH%/*}/files"  # Replace manifest.json with files
                        echo "Looking for catalog files in: $CSV_DIR"
                        CATALOG_FILE=$(mc ls --recursive "$alias/$CATALOG_BUCKET/$CSV_DIR/" | grep -E "\.(csv|ndjson)$" | head -n 1 | awk '{print $NF}')
                        if [ -n "$CATALOG_FILE" ]; then
                            # Store the complete path including directory
                            FULL_CSV_PATH="$CSV_DIR/$CATALOG_FILE"
                            return 0
                        fi
                        echo "Could not find catalog file in $CSV_DIR"
                        return 1
                    else
                        echo "Could not find manifest path in job status"
                        return 1
                    fi
                fi
            fi
            
            sleep 5
        done
    else
        echo "Failed to extract job ID from output: $BATCH_OUTPUT"
        return 1
    fi
}

# Function to display catalog results
display_catalog_results() {
    local alias=$1
    local catalog_bucket=$2
    local file_path=$3
    local description=$4
    local size_filter=$5
    
    echo "=== Results from $description ==="
    if [ -n "$file_path" ]; then
        echo "Found catalog file: $file_path"
        if [ -n "$size_filter" ]; then
            echo "All files in filtered catalog (should all be $size_filter bytes):"
            # For JSON format, use jq to extract file paths
            mc cat "$alias/$catalog_bucket/$file_path" | jq -r '.Key'
        else
            echo "Files with exactly $LOOK_FOR_SIZE bytes:"
            mc sql --recursive --query "select _2 as path from S3Object where cast(_3 as integer) = $LOOK_FOR_SIZE" "$alias/$catalog_bucket/$file_path"
        fi
    else
        echo "No catalog file found for $description"
    fi
}

# Parse command line arguments
CLEANUP_ONLY=false
while [[ $# -gt 0 ]]
do
    case $1 in
        --alias)
            ALIAS="$2"
            shift 2
            ;;
        --bucket)
            BUCKET="$2"
            shift 2
            ;;
        --folders)
            NUM_FOLDERS="$2"
            shift 2
            ;;
        --files)
            FILES_PER_FOLDER="$2"
            shift 2
            ;;
        --cleanup)
            CLEANUP_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --alias <alias> --bucket <bucket> [--folders <num_folders>] [--files <files_per_folder>] [--cleanup]"
            exit 1
            ;;
    esac
done

# Set default values
NUM_FOLDERS=${NUM_FOLDERS:-10}
FILES_PER_FOLDER=${FILES_PER_FOLDER:-10}

# Handle cleanup-only mode
if [ "$CLEANUP_ONLY" = true ]; then
    if [ -z "$ALIAS" ] || [ -z "$BUCKET" ]; then
        echo "Usage: $0 --alias <alias> --bucket <bucket> --cleanup"
        exit 1
    fi
    
    # Verify alias configuration
    get_alias_config "$ALIAS"
    
    # Perform cleanup
    cleanup_catalog_resources "$ALIAS" "$BUCKET"
    exit 0
fi

# Validate required arguments
if [ -z "$ALIAS" ] || [ -z "$BUCKET" ]
then
    echo "Usage: $0 --alias <alias> --bucket <bucket> [--folders <num_folders>] [--files <files_per_folder>] [--cleanup]"
    echo "  --folders: Number of folders to create (default: 10)"
    echo "  --files: Number of files per folder (default: 10)"
    echo "  --cleanup: Clean up catalog files and buckets only"
    exit 1
fi

# Check for required tools
check_jq
check_openssl

# Verify alias configuration
get_alias_config "$ALIAS"

# Check catalog support
check_catalog_support "$ALIAS"

# Create temporary directory for files
TEMP_DIR=$(mktemp -d)
if [ ! -d "$TEMP_DIR" ]
then
    echo "Error: Failed to create temporary directory"
    exit 1
fi

# Ensure cleanup on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

# Ensure bucket exists
mc mb "$ALIAS/$BUCKET" &> /dev/null || true

# Generate random folder for special file
SPECIAL_FOLDER=$((RANDOM % NUM_FOLDERS))
SPECIAL_FILE_INDEX=$((RANDOM % FILES_PER_FOLDER))
LOOK_FOR_SIZE=555
CATALOG_BUCKET="catalog"

echo "Creating folders and files..."
total_files=$((NUM_FOLDERS * FILES_PER_FOLDER))
current_file=0

for folder_idx in $(seq 0 $((NUM_FOLDERS-1)))
do
    FOLDER_NAME="folder_$(generate_random_name 5)"
    
    for file_idx in $(seq 0 $((FILES_PER_FOLDER-1)))
    do
        FILE_NAME="$(generate_random_name)"
        FILE_PATH="$TEMP_DIR/$FILE_NAME"
        
        SIZE=$LOOK_FOR_SIZE
        if ! [[ $folder_idx -eq $SPECIAL_FOLDER && $file_idx -eq $SPECIAL_FILE_INDEX ]]
        then
            # Create random sized file (1-100KB), avoiding 555 bytes
            while [ $SIZE -eq $LOOK_FOR_SIZE ]
            do
                SIZE=$((RANDOM % 102400 + 1))
            done
        fi
        generate_random_data $SIZE "$FILE_PATH"
        
        # Upload file to MinIO
        mc cp "$FILE_PATH" "$ALIAS/$BUCKET/$FOLDER_NAME/$FILE_NAME" &> /dev/null
        rm -f "$FILE_PATH"
        
        # Show progress
        current_file=$((current_file + 1))
        echo -ne "\rProgress: $current_file/$total_files"
    done
done

echo -e "\nCreated $NUM_FOLDERS folders with $FILES_PER_FOLDER files each in bucket $BUCKET"
echo "One file has exactly $LOOK_FOR_SIZE bytes"

# Create catalog bucket
echo "Creating catalog bucket..."
mc mb "$ALIAS/$CATALOG_BUCKET" &> /dev/null || true
echo "Catalog bucket created"

# Create catalog.yaml file without filters
create_catalog_config "catalog.yaml" "$BUCKET" "$CATALOG_BUCKET" "" "CSV"

# Start the first catalog job (without filters)
if run_catalog_job "$ALIAS" "catalog.yaml" "first catalog job (without filters)"; then
    FULL_CSV_PATH_1="$FULL_CSV_PATH"
else
    exit 1
fi

# Create catalog.yaml file with size filter
create_catalog_config "catalog_with_filter.yaml" "$BUCKET" "$CATALOG_BUCKET" "$LOOK_FOR_SIZE" "JSON"

# Start the second catalog job (with size filter)
if run_catalog_job "$ALIAS" "catalog_with_filter.yaml" "second catalog job (with size filter)"; then
    FULL_JSON_PATH_2="$FULL_CSV_PATH"
else
    exit 1
fi

# Display results from both catalog jobs
display_catalog_results "$ALIAS" "$CATALOG_BUCKET" "$FULL_CSV_PATH_1" "first catalog job (without filters)" ""
display_catalog_results "$ALIAS" "$CATALOG_BUCKET" "$FULL_JSON_PATH_2" "second catalog job (with size filter)" "$LOOK_FOR_SIZE" 
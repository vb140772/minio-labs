# MinIO Catalog Test Script

## Overview

This script demonstrates and tests MinIO's catalog feature by creating test data and running catalog jobs with different configurations. It showcases the efficiency and flexibility of using catalog filters to process only relevant objects.

## What It Does

The script performs the following operations:

1. **Creates Test Data**: Generates random files with varying sizes in multiple folders
   - Creates only **one file with exactly 555 bytes** (the target for filtering)
   - All other files have random sizes (1-100KB, avoiding 555 bytes)
2. **Runs Two Catalog Jobs**: 
   - One without filters (catalogs all files)
   - One with size filter (catalogs only files of specific size)
3. **Compares Results**: Shows how filtering affects catalog performance and output
4. **Demonstrates Two File Finding Approaches**:
   - **Unfiltered catalog**: Uses `mc sql` queries against the complete catalog data to find the 555-byte file
     - Executes SQL queries like `SELECT * FROM s3object WHERE size = 555` against the CSV catalog output
     - Searches through all cataloged files to find matches based on size criteria
     - Requires parsing through the entire unfiltered dataset to locate specific files
   - **Filtered catalog**: Directly displays the filtered catalog data which contains only the 555-byte file

## Why Use This Script

### Purpose
- **Performance Testing**: Demonstrates the efficiency gains from using catalog filters
- **Feature Validation**: Tests MinIO's catalog functionality with real data
- **Learning Tool**: Shows how to configure and use catalog jobs with different formats
- **Comparison**: Illustrates the difference between filtered and unfiltered catalog operations

### Benefits
- **Faster Processing**: Filtered catalogs process only relevant objects
- **Reduced Storage**: Smaller output files when using filters
- **Format Flexibility**: Supports both CSV and NDJSON output formats
- **Real-world Testing**: Uses realistic data patterns and sizes

## How It Works

### Prerequisites
- MinIO Client (`mc`) configured with an alias
- `jq` for JSON processing
- `openssl` for random data generation
- Catalog support enabled on the MinIO cluster

### Script Flow

#### 1. Setup and Validation
```bash
# Check required tools
check_jq
check_openssl

# Validate MinIO configuration
get_alias_config "$ALIAS"
check_catalog_support "$ALIAS"
```

#### 2. Test Data Generation
- Creates a specified number of folders (default: 10)
- Generates random files in each folder (default: 10 per folder)
- Ensures one file has exactly 555 bytes (the target size for filtering)
- All other files have random sizes (1-100KB, avoiding 555 bytes)

#### 3. First Catalog Job (Without Filters)
```yaml
catalog:
  apiVersion: v1
  bucket: test-bucket
  destination:
    bucket: catalog
    format: CSV
    compression: off
  name:
    - match: "*"
  versions: current
```
- Processes ALL files in the bucket
- Outputs CSV format
- Uses `mc sql` to query for files with specific size

#### 4. Second Catalog Job (With Size Filter)
```yaml
catalog:
  apiVersion: v1
  bucket: test-bucket
  destination:
    bucket: catalog
    format: JSON
    compression: off
  name:
    - match: "*"
  versions: current
  filters:
    size:
      equalTo: 555
```
- Processes ONLY files that are exactly 555 bytes
- Outputs NDJSON format
- Uses `jq` to extract file paths directly

#### 5. Results Comparison
- Shows files found by each approach
- Demonstrates efficiency differences
- Validates filter accuracy

## Usage

### Basic Usage
```bash
./create_test_files.sh --alias my-minio --bucket test-bucket
```

### Advanced Usage
```bash
./create_test_files.sh \
  --alias my-minio \
  --bucket test-bucket \
  --folders 20 \
  --files 50
```

### Cleanup Usage
```bash
# Clean up all created resources
./create_test_files.sh --alias my-minio --bucket test-bucket --cleanup
```

### Parameters
- `--alias`: MinIO alias name (required)
- `--bucket`: Target bucket name (required)
- `--folders`: Number of folders to create (default: 10)
- `--files`: Number of files per folder (default: 10)
- `--cleanup`: Clean up catalog files and buckets (optional)

## Cleanup Functionality

The script includes a cleanup option that removes all resources created during testing:

### What Gets Cleaned Up
- **Catalog YAML files**: `catalog.yaml` and `catalog_with_filter.yaml`
- **Catalog bucket**: The `catalog` bucket containing catalog output files
- **Test bucket**: The bucket specified with `--bucket` containing test data

### Cleanup Examples

#### Cleanup Only (without running tests)
```bash
./create_test_files.sh --alias my-minio --bucket test-bucket --cleanup
```

#### Run Tests Then Cleanup
```bash
# Run the tests
./create_test_files.sh --alias my-minio --bucket test-bucket

# Clean up afterwards
./create_test_files.sh --alias my-minio --bucket test-bucket --cleanup
```

#### One-liner (run tests and cleanup)
```bash
./create_test_files.sh --alias my-minio --bucket test-bucket && \
./create_test_files.sh --alias my-minio --bucket test-bucket --cleanup
```

### Cleanup Safety Features
- **Existence checks**: Only removes files/buckets that exist
- **Force removal**: Uses `mc rb --force` to remove buckets with contents
- **Clear feedback**: Provides status messages for each cleanup operation
- **Validation**: Still validates alias configuration in cleanup mode

## Key Functions

### `create_catalog_config()`
Creates catalog configuration files with optional filters and format selection.

### `run_catalog_job()`
Handles the complete catalog job lifecycle:
- Starts the job
- Monitors progress
- Extracts output file path
- Handles errors

### `display_catalog_results()`
Displays results from catalog jobs:
- For CSV: Uses `mc sql` queries
- For NDJSON: Uses `jq` for parsing

### `cleanup_catalog_resources()`
Removes all test resources:
- Deletes catalog YAML configuration files
- Removes catalog and test buckets
- Provides status feedback

## Output Formats

### CSV Format
- Used for unfiltered catalogs
- Queryable with `mc sql`
- Good for complex queries and analysis

### NDJSON Format
- Used for filtered catalogs
- Processed with `jq`
- Efficient for streaming and simple extractions

## Expected Results

### First Job (Unfiltered)
- Processes all files (e.g., 100 files)
- Takes longer to complete
- Larger output file
- Requires SQL query to find specific files

### Second Job (Filtered)
- Processes only matching files (e.g., 1 file)
- Completes much faster
- Smaller output file
- Direct access to relevant files

## Error Handling

The script includes comprehensive error handling:
- Validates required tools and dependencies
- Checks MinIO configuration and catalog support
- Monitors job status and handles failures
- Provides clear error messages

## Cleanup

- Temporary files are automatically cleaned up
- Uses trap to ensure cleanup on script exit
- Buckets and catalog files remain for inspection
- Use `--cleanup` option to remove all test resources

## Troubleshooting

### Common Issues
1. **Catalog not supported**: Ensure your MinIO cluster supports catalog feature
2. **Missing tools**: Install `jq` and `openssl`
3. **Invalid alias**: Check `mc config` for correct alias name
4. **Permission errors**: Verify bucket access permissions

### Debug Tips
- Check job status manually: `mc batch status <alias>/ <job-id>`
- Inspect catalog files: `mc ls <alias>/catalog/`
- View job logs for detailed error information

## Performance Considerations

- **Filtered catalogs** are significantly faster for large datasets
- **JSON format** is more efficient for simple data extraction
- **CSV format** is better for complex queries and analysis
- **Size filters** are particularly effective for finding specific file types

## Use Cases

This script is useful for:
- **Performance benchmarking** of catalog operations
- **Testing catalog filters** with real data
- **Learning MinIO catalog features**
- **Validating catalog configurations**
- **Comparing different output formats** 
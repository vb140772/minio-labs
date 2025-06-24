mc mb cluster-1/sourcebucket01
mc mb cluster-1/sourcebucket02
mc version enable cluster-1/sourcebucket01
mc version enable cluster-1/sourcebucket02
dd if=/dev/zero of=testfile1GB bs=1M count=1024
mc put testfile1GB cluster-1/sourcebucket01/testfile01
mc put testfile1GB cluster-1/sourcebucket01/testfile02
mc put testfile1GB cluster-1/sourcebucket02/testfile03
mc put testfile1GB cluster-1/sourcebucket02/testfile04
mc ls -r cluster-1

mc mb cluster-2/sourcebucket01
mc version enable cluster-2/sourcebucket01

mc replicate add cluster-1/sourcebucket01 \
	--remote-bucket 'http://admin:password123@minio-2-1:9000/sourcebucket01'

mc idp ldap add cluster-2 \
	server_addr=192.168.104.11:389 \
	server_insecure=on \
	lookup_bind_dn="cn=admin,dc=nodomain" \
	lookup_bind_password=val6@ery \
	user_dn_search_base_dn="ou=users,dc=nodomain" \
	user_dn_search_filter="(&(objectClass=inetOrgPerson)(uid=%s))" \
	group_search_base_dn="ou=groups,dc=nodomain" \
	group_search_filter="(&(objectClass=groupOfNames)(member=%d))"

mc admin replicate add cluster-1 cluster-2

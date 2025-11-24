deploy_cassandra_cluster() {
    local num_nodes=$1
    echo "=== Deploying $num_nodes Cassandra containers ==="

    compose_file="docker-compose-cassandra-${num_nodes}.yml"

    docker compose -f $compose_file down -v 2>/dev/null

    echo "Starting new Cassandra cluster"
    docker compose -f $compose_file up -d

    echo "Waiting for Cassandra cluster to be Up"
    local attempts=0
    local max_wait_attempts=30

    while [ $attempts -lt $max_wait_attempts ]; do
        sleep 10
        # verify if number of nodes'UN' (Up/Normal) is the expected number
        local up_nodes=$(docker exec cassandra1 nodetool status | grep -c 'UN')
        if [ "$up_nodes" -eq "$num_nodes" ]; then
            echo "Cluster is Up/Normal with $up_nodes/$num_nodes nodes."
            break
        fi

        attempts=$((attempts + 1))
        echo "  Attempt $attempts/$max_wait_attempts: $up_nodes/$num_nodes nodes are Up/Normal..."
    done

    if [ $attempts -eq $max_wait_attempts ]; then
        echo "Cassandra cluster did not become fully ready."
        docker exec cassandra1 nodetool status
        exit 1
    fi
    
    echo "Checking cluster state:"
    docker exec cassandra1 nodetool status
}

if [ $# -eq 0 ]; then
    echo "Usage: $0 <nodes>"
    exit 1
fi

num_nodes=$1
deploy_cassandra_cluster $num_nodes

echo "Creating YCSB keyspace & table..."
max_attempts=20
attempt=0
echo "Waiting for CQL shell to be ready..."
while [ $attempt -lt $max_attempts ]; do
    if docker exec cassandra1 cqlsh -e "DESCRIBE KEYSPACES;" &>/dev/null; then
        echo "✓ CQL shell is ready"
        break
    fi
    attempt=$((attempt + 1))
    echo "  Attempt $attempt/$max_attempts..."
    sleep 10
done

if [ $attempt -eq $max_attempts ]; then
    echo "CQL shell never became ready"
    exit 1
fi

echo "Creating keyspace..."
if docker exec cassandra1 cqlsh -e "CREATE KEYSPACE IF NOT EXISTS ycsb WITH replication = {'class':'SimpleStrategy','replication_factor':$num_nodes};"; then
    echo "Keyspace created"
else
    echo "Failed to create keyspace"
    exit 1
fi

echo "Creating usertable..."
if docker exec cassandra1 cqlsh -e "CREATE TABLE IF NOT EXISTS ycsb.usertable (y_id text PRIMARY KEY, field0 text, field1 text, field2 text, field3 text, field4 text, field5 text, field6 text, field7 text, field8 text, field9 text);"; then
    echo "Table created"
else
    echo "Failed to create table"
    exit 1
fi

echo ""
echo "Writing YCSB cassandra.properties..."

cat > ycsb-0.17.0/bin/cassandra.properties << EOF
hosts=127.0.0.1
port=9042
cassandra.keyspace=ycsb
readconsistencylevel=ONE
writeconsistencylevel=ONE
EOF


echo "Cassandra cluster with $num_nodes nodes deployed."

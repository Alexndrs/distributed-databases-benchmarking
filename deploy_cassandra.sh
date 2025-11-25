#!/bin/bash

set -e

deploy_cassandra_cluster() {
    local num_nodes=$1
    echo "=== Deploying $num_nodes Cassandra containers ==="

    compose_file="docker-compose-cassandra-${num_nodes}.yml"

    echo "Stopping and removing all Cassandra containers..."
    docker compose -f "$compose_file" down -v --remove-orphans 2>/dev/null || true
    docker ps -a --filter "name=cassandra" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
    
    echo "Removing all Cassandra volumes..."
    docker volume ls -q | grep -E '(cassandra|tp2)' | xargs -r docker volume rm 2>/dev/null || true
    
    echo "Cleaning networks..."
    docker network prune -f 2>/dev/null || true
    
    echo "Waiting 5 seconds for cleanup..."
    sleep 5

    echo "Starting Cassandra cluster..."
    docker compose -f $compose_file up -d

    echo "Waiting for cluster initialization (60sec)..."
    sleep 60
    
    echo "Checking containers are running..."
    local nodes=()
    for i in $(seq 1 $num_nodes); do
        nodes+=("cassandra$i")
    done
    
    for node in "${nodes[@]}"; do
        local container_wait=0
        while [ $container_wait -lt 15 ]; do
            if docker ps --filter "name=$node" --filter "status=running" | grep -q $node; then
                echo "  $node container is running"
                break
            fi
            sleep 5
            container_wait=$((container_wait + 1))
        done
        if [ $container_wait -eq 15 ]; then
            echo "$node container failed to start"
            docker logs $node
            exit 1
        fi
    done

    echo "Waiting for Cassandra nodes to be ready..."
    local overall_attempts=0
    local max_overall_attempts=60
    
    while [ $overall_attempts -lt $max_overall_attempts ]; do
        local ready_nodes=0
        
        for node in "${nodes[@]}"; do
            if docker exec $node nodetool status &>/dev/null; then
                ready_nodes=$((ready_nodes + 1))
            fi
        done
        
        echo "  $ready_nodes/$num_nodes nodes responding to nodetool..."
        
        if [ $ready_nodes -eq $num_nodes ]; then
            echo "All nodes responding to nodetool"
            break
        fi
        
        sleep 10
        overall_attempts=$((overall_attempts + 1))
    done

    if [ $overall_attempts -eq $max_overall_attempts ]; then
        echo "Some nodes never responded to nodetool"
        for node in "${nodes[@]}"; do
            echo "=== $node status ==="
            docker exec $node nodetool status 2>&1 || echo "Not responsive"
        done
        exit 1
    fi

    echo "Waiting for cluster to form..."
    local cluster_attempts=0
    local max_cluster_attempts=50
    
    while [ $cluster_attempts -lt $max_cluster_attempts ]; do
        local status_output=$(docker exec cassandra1 nodetool status 2>/dev/null || echo "")
        local up_nodes=$(echo "$status_output" | grep -c 'UN' || echo "0")
        
        echo "Attempt $((cluster_attempts + 1))/$max_cluster_attempts: $up_nodes/$num_nodes nodes UP..."
        
        if [ "$up_nodes" -eq "$num_nodes" ]; then
            echo "Cluster fully formed with $up_nodes nodes UP!"
            break
        fi
        
        if [ $((cluster_attempts % 5)) -eq 0 ]; then
            echo "Current cluster status:"
            docker exec cassandra1 nodetool status 2>/dev/null | grep -E '(UN|UJ|DN|D|J|R)N' || echo "Waiting for cluster..."
        fi
        
        sleep 10
        cluster_attempts=$((cluster_attempts + 1))
    done

    if [ $cluster_attempts -eq $max_cluster_attempts ]; then
        echo "Cluster never fully formed"
        echo "Final cluster status:"
        docker exec cassandra1 nodetool status 2>/dev/null || echo "cassandra1 not accessible"
        echo ""
        echo "Debug info:"
        for node in "${nodes[@]}"; do
            echo "=== $node ==="
            docker exec $node nodetool info 2>&1 | grep "ID\|Status" || echo "Not responsive"
        done
        exit 1
    fi

    echo "Final cluster state:"
    docker exec cassandra1 nodetool status
}

create_ycsb_schema() {
    local num_nodes=$1
    echo "Creating YCSB keyspace and table..."
    
    echo "Waiting for CQL to be ready..."
    local cql_attempts=0
    while [ $cql_attempts -lt 30 ]; do
        if docker exec cassandra1 cqlsh -e "DESCRIBE KEYSPACES;" &>/dev/null; then
            echo "✓ CQL is ready"
            break
        fi
        sleep 5
        cql_attempts=$((cql_attempts + 1))
    done

    if [ $cql_attempts -eq 30 ]; then
        echo "CQL never became ready"
        exit 1
    fi

    echo "Creating keyspace..."
    docker exec cassandra1 cqlsh -e "
        CREATE KEYSPACE IF NOT EXISTS ycsb 
        WITH replication = {
            'class': 'SimpleStrategy',
            'replication_factor': $num_nodes
        };"
    echo "Keyspace created"

    echo "Creating table..."
    docker exec cassandra1 cqlsh -e "
        CREATE TABLE IF NOT EXISTS ycsb.usertable (
            y_id text PRIMARY KEY,
            field0 text,
            field1 text,
            field2 text,
            field3 text,
            field4 text,
            field5 text,
            field6 text,
            field7 text,
            field8 text,
            field9 text
        );"
    echo "Table created"

    echo "Creating YCSB properties file..."
    cat > ycsb-0.17.0/bin/cassandra.properties << EOF
hosts=127.0.0.1
port=9042
cassandra.keyspace=ycsb
readconsistencylevel=ONE
writeconsistencylevel=ONE
cassandra.connecttimeoutmillis=10000
cassandra.readtimeoutmillis=10000
EOF
    echo "YCSB properties file created"
}

# Validation des arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <nodes>"
    echo "Example: $0 3"
    exit 1
fi

num_nodes=$1

echo "Starting deployment of $num_nodes-node Cassandra cluster..."
deploy_cassandra_cluster $num_nodes
create_ycsb_schema $num_nodes

echo ""
echo "Cassandra cluster with $num_nodes nodes successfully deployed!"
echo "Cluster status:"
docker exec cassandra1 nodetool status
echo ""
echo "YCSB can connect using: hosts=cassandra1, port=9042"
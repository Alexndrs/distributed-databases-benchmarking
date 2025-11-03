deploy_mongo_cluster() {
    local num_nodes=$1
    echo "=== Deploying $num_nodes mongo containers ==="
    
    echo "Cleaning existing containers"
    docker compose -f docker-compose-mongo-${num_nodes}.yml down -v 2>/dev/null
    docker rm -f $(docker ps -aq --filter "name=mongo") 2>/dev/null
    
    echo "Creating new containers"
    docker compose -f docker-compose-mongo-${num_nodes}.yml up -d
    
    echo "Waiting for containers to start (30 seconds)..."
    sleep 30
    
    echo "Init replica set..."
    local members=""
    for i in $(seq 1 $num_nodes); do
        if [ $i -eq 1 ]; then
            members="{_id: $((i-1)), host: \"mongo${i}:27017\"}"
        else
            members="${members}, {_id: $((i-1)), host: \"mongo${i}:27017\"}"
        fi
    done
    docker exec -it mongo1 mongosh --eval "
    rs.initiate({
        _id: 'rs0',
        members: [$members]
    })
    "
    
    echo "Waiting for replica set to elect a PRIMARY (30 seconds)..."
    sleep 30
    
    echo "Verify replica set status"
    docker exec -it mongo1 mongosh --eval "rs.status()" | grep -E "name|stateStr"
    
    echo "Updating mongodb.properties"
    local connection_string="mongodb://"
    for i in $(seq 1 $num_nodes); do
        local port=$((27016 + i))
        if [ $i -eq 1 ]; then
            connection_string="${connection_string}mongo${i}:${port}"
        else
            connection_string="${connection_string},mongo${i}:${port}"
        fi
    done
    connection_string="${connection_string}/?replicaSet=rs0"
    
    cat > ycsb-0.17.0/bin/mongodb.properties << EOF
mongodb.url=${connection_string}
mongodb.database=ycsb
EOF
    
    echo "$num_nodes mongodb nodes deployed"
}

# Vérifier l'argument
if [ $# -eq 0 ]; then
    echo "Usage: $0 <nombre_de_noeuds>"
    echo "Exemple: $0 3"
    exit 1
fi

deploy_mongo_cluster $1

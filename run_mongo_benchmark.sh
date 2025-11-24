if [ $# -eq 0 ]; then
    echo "Usage: $0 <nombre_de_noeuds>"
    echo "Exemple: $0 3"
    echo "         $0 5"
    exit 1
fi

num_nodes=$1
WORKLOADS=("workloada" "workloadb" "workloadc")

results_dir="results_mongo_${num_nodes}"
mkdir -p "$results_dir"


clean_database() {
    echo "Cleaning database..."
    docker exec mongo1 mongosh --quiet --eval "
        db = db.getSiblingDB('ycsb');
        db.dropDatabase();
    " 2>/dev/null
    
    echo "Waiting for deletion to propagate (5 seconds)..."
    sleep 5
    
    # verify it's clean
    local count=$(docker exec mongo1 mongosh --quiet --eval "
        db = db.getSiblingDB('ycsb');
        db.usertable.countDocuments({});
    " 2>/dev/null | grep -oE '[0-9]+' | tail -n 1)

    if [ -z "$count" ]; then
        count=0
    fi
    
    echo "Remaining documents: $count"
}


echo "========================================"
echo "Config with $num_nodes mongodb nodes"
echo "========================================"
echo ""

# Deploy the cluster
./deploy_mongo.sh $num_nodes
sleep 10

for workload in "${WORKLOADS[@]}"; do
    echo ""
    echo "___ Testing $workload with $num_nodes nodes ___"
    
    for i in {1..10}; do
        echo ""
        echo "=== Run $i/10 for $workload ==="
        
        # Load
        echo "Loading data..."
        cd ycsb-0.17.0/bin
        ./ycsb load mongodb -s -P ../workloads/$workload -P mongodb.properties > ../../${results_dir}/${workload}_${num_nodes}nodes_load_${i}.txt 2>&1

        # wait for replication
        echo "Waiting for replication (2 seconds)..."
        sleep 2
        
        # Run
        ./ycsb run mongodb -s -P ../workloads/$workload -P mongodb.properties > ../../${results_dir}/${workload}_${num_nodes}nodes_run_${i}.txt 2>&1
        
        # Clean database
        cd ../..
        clean_database
    done
done

echo "Tests finished for $num_nodes nodes"
echo "See results in ./${results_dir}/"

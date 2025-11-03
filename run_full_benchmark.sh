mkdir -p results

WORKLOADS=("workloada" "workloadb" "workloadc")
NODES=(3 5)

clean_database() {
    echo "Cleaning database..."
    docker exec mongo1 mongosh --quiet --eval "
        use ycsb;
        db.dropDatabase();
    " 2>/dev/null
    
    # wait a few seconds
    sleep 3
    
    # verify it's clean
    local count=$(docker exec mongo1 mongosh --quiet --eval "use ycsb; db.usertable.countDocuments({})" 2>/dev/null | tail -n 1)
    echo "Remaining data: $count"
}


for num_nodes in "${NODES[@]}"; do
    echo "========================================"
    echo "Config with $num_nodes mongodb nodes"
    echo "========================================"
    
    # Deploy the cluster
    ./deploy_mongo.sh $num_nodes
    sleep 10
    
    for workload in "${WORKLOADS[@]}"; do
        echo "___ Testing $workload with $num_nodes nodes ___"
        
        for i in {1..10}; do
            echo "Run $i/10 for $workload"
            
            # Load
            cd ycsb-0.17.0/bin
            ./ycsb load mongodb -s -P ../workloads/$workload -P mongodb.properties > ../../results/${workload}_${num_nodes}nodes_load_${i}.txt 2>&1

            load_status=$?
            if [ $load_status -ne 0 ]; then
                echo "⚠️ Error while loading"
                cat ../../results/${workload}_${num_nodes}nodes_load_${i}.txt | grep -i error
            fi

            
            # Run
            ./ycsb run mongodb -s -P ../workloads/$workload -P mongodb.properties > ../../results/${workload}_${num_nodes}nodes_run_${i}.txt 2>&1
            
            # Clean database
            cd ../..
            clean_database
        done
    done
    
    echo "✅ Tests finished for $num_nodes nodes"
    echo ""
done

echo "All benchmarks done !"
echo "See results in ./results/"

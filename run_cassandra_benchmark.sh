set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <nodes>"
    echo "Exemple: $0 3"
    echo "         $0 1"
    exit 1
fi

num_nodes=$1
WORKLOADS=("workloada" "workloadb" "workloadc")

results_dir="results_cassandra_${num_nodes}"
mkdir -p "$results_dir"

clean_database() {
    echo "Cleaning Cassandra database..."
    docker exec cassandra1 cqlsh -e "TRUNCATE ycsb.usertable;" 2>/dev/null || true
    sleep 3
    
    local count=$(docker exec cassandra1 cqlsh -e "SELECT COUNT(*) FROM ycsb.usertable;" 2>/dev/null | grep -oE '[0-9]+' | tail -n 1 || echo "0")
    
    if [ "$count" != "0" ]; then
        echo "Warning: Table not empty after truncate (count: $count), retrying..."
        docker exec cassandra1 cqlsh -e "TRUNCATE ycsb.usertable;" 2>/dev/null || true
        sleep 3
    fi
    
    echo "Database cleaned"
}

echo "========================================"
echo "Benchmark with $num_nodes Cassandra nodes"
echo "========================================"
echo ""

./deploy_cassandra.sh $num_nodes

echo "Waiting extra 30 seconds for cluster stability..."
sleep 30

echo "Final cluster check before benchmark..."
docker exec cassandra1 nodetool status

for workload in "${WORKLOADS[@]}"; do
    echo ""
    echo "=== Testing $workload with $num_nodes nodes ==="

    for i in {1..10}; do
        echo ""
        echo "Run $i/10 for $workload"
        
        clean_database

        echo "Loading data..."
        cd ycsb-0.17.0/bin
        ./ycsb load cassandra-cql -s -P ../workloads/$workload -P cassandra.properties > "../../${results_dir}/${workload}_${num_nodes}nodes_load_${i}.txt" 2>&1
        cd ../..
        
        sleep 2

        echo "Running workload..."
        cd ycsb-0.17.0/bin
        ./ycsb run cassandra-cql -s -P ../workloads/$workload -P cassandra.properties > "../../${results_dir}/${workload}_${num_nodes}nodes_run_${i}.txt" 2>&1
        cd ../..
        
        echo "Run $i/10 completed for $workload"
    done
    
    echo "All runs completed for $workload"
done

echo ""
echo "Final database cleanup..."
clean_database

echo ""
echo "========================================"
echo "Benchmark completed for $num_nodes nodes!"
echo "Results saved in: ./${results_dir}/"
echo "========================================"
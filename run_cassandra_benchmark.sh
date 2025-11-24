if [ $# -eq 0 ]; then
    echo "Usage: $0 <nombre_de_noeuds>"
    echo "Exemple: $0 3"
    echo "         $0 5"
    exit 1
fi

num_nodes=$1
WORKLOADS=("workloada" "workloadb" "workloadc")

results_dir="results_cassandra_${num_nodes}"
mkdir -p "$results_dir"

clean_database() {
    echo "Cleaning Cassandra keyspace..."
    docker exec cassandra1 cqlsh -e "TRUNCATE ycsb.usertable;" 2>/dev/null
    sleep 5
    local count=$(docker exec cassandra1 cqlsh -e "SELECT COUNT(*) FROM ycsb.usertable;" 2>/dev/null | grep -oE '[0-9]+' | tail -n 1)
    
    if [ -z "$count" ]; then
        count=0
    fi
    
    echo "Remaining records: $count"

}


echo "========================================"
echo "Config with $num_nodes Cassandra nodes"
echo "========================================"
echo ""

./deploy_cassandra.sh $num_nodes

echo "Waiting extra 20 seconds for stability..."
sleep 20

for workload in "${WORKLOADS[@]}"; do
    echo "=== Testing $workload with $num_nodes nodes ==="

    for i in {1..10}; do
        echo "Run $i/10"

        cd ycsb-0.17.0/bin

        ./ycsb load cassandra-cql -s -P ../workloads/$workload -P cassandra.properties > "../../${results_dir}/${workload}_${num_nodes}nodes_load_${i}.txt" 2>&1

        sleep 3

        ./ycsb run cassandra-cql -s -P ../workloads/$workload -P cassandra.properties > "../../${results_dir}/${workload}_${num_nodes}nodes_run_${i}.txt" 2>&1

        cd ../..

        clean_database
    done
done

echo "Tests finished for $num_nodes nodes"
echo "See results in ./${results_dir}/"
echo "cleaning database"
clean_database

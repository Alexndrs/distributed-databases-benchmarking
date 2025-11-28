import os
import re
import numpy as np
import pandas as pd
from collections import defaultdict

BASE_DIR = "."  # Directory containing results_mongo_3 and results_mongo_5

def parse_ycsb_file(filepath):
    metrics = {}

    # Patterns standards YCSB
    patterns = {
        "throughput": r"\[OVERALL\], Throughput\(ops/sec\), ([0-9\.]+)",
        "runtime_ms": r"\[OVERALL\], RunTime\(ms\), ([0-9]+)",
        "insert_avg": r"\[INSERT\], AverageLatency\(us\), ([0-9\.]+)",
        "read_avg": r"\[READ\], AverageLatency\(us\), ([0-9\.]+)",
        "update_avg": r"\[UPDATE\], AverageLatency\(us\), ([0-9\.]+)",
        "insert_95": r"\[INSERT\], 95thPercentileLatency\(us\), ([0-9\.]+)",
        "read_95": r"\[READ\], 95thPercentileLatency\(us\), ([0-9\.]+)",
        "update_95": r"\[UPDATE\], 95thPercentileLatency\(us\), ([0-9\.]+)",
    }

    with open(filepath, "r") as f:
        text = f.read()

    for key, pattern in patterns.items():
        m = re.search(pattern, text)
        if m:
            metrics[key] = float(m.group(1))

    return metrics


def load_all_results():
    '''
    
    Results structure:
    results[db][nodes][workload][phase][idx] = metrics
    example:
    results["mongo"][3]["a"]["run"][4] -> metrics dict
    '''
    results = defaultdict(lambda: defaultdict(lambda: defaultdict(lambda: defaultdict(dict))))

    for dirname in os.listdir(BASE_DIR):
        m = re.match(r"results_(mongo|cassandra|redis)_([35])$", dirname)
        if not m:
            continue

        db = m.group(1)                   # "mongo" or "cassandra" or "redis"
        nodes = int(m.group(2))           # 3 or 5
        folder = os.path.join(BASE_DIR, dirname)

        for filename in os.listdir(folder):
            if not filename.endswith(".txt"):
                continue

            # filename pattern:
            # workloada_3nodes_load_1.txt
            match = re.match(
                r"workload([abc])_([35])nodes_(load|run)_([0-9]+)\.txt",
                filename
            )
            if not match:
                continue

            workload = match.group(1)
            nodes2 = int(match.group(2))
            phase = match.group(3)
            idx = int(match.group(4))

            if nodes != nodes2:
                continue

            filepath = os.path.join(folder, filename)
            metrics = parse_ycsb_file(filepath)

            results[db][nodes][workload][phase][idx] = metrics

    return results


def compute_statistics(results):
    '''
    compute mean and stddev for each metric across samples
    '''
    stats = []

    for db, db_dict in results.items():
        for nodes, workload_dict in db_dict.items():
            for workload, phases in workload_dict.items():
                for phase, samples in phases.items():

                    metrics_by_key = defaultdict(list)

                    for idx, metric_dict in samples.items():

                        # --- Compute new global latencies per file ---
                        avg_global, p95_global = compute_global_latencies(workload, phase, metric_dict)

                        if avg_global is not None:
                            metric_dict["avg_latency_global"] = avg_global
                        if p95_global is not None:
                            metric_dict["p95_global"] = p95_global

                        # Accumulate metrics
                        for key, value in metric_dict.items():
                            metrics_by_key[key].append(value)

                    # Reduce by mean/std
                    for metric_name, values in metrics_by_key.items():
                        arr = np.array(values)
                        stats.append({
                            "db": db,
                            "nodes": nodes,
                            "workload": workload,
                            "phase": phase,
                            "metric": metric_name,
                            "mean": arr.mean(),
                            "std": arr.std(),
                            "n": len(arr)
                        })

    return pd.DataFrame(stats)

def compute_global_latencies(workload, phase, metrics):
    '''
    Return (avg_global, p95_global) with correct YCSB semantics:
    - LOAD phase always = INSERT only
    - RUN phase follows workload proportions
    '''
    # LOAD PHASE = only INSERT
    if phase == "load":
        avg = metrics.get("insert_avg")
        p95 = metrics.get("insert_95")
        return avg, p95

    # RUN PHASE below
    if workload == "a":
        read_avg = metrics.get("read_avg")
        update_avg = metrics.get("update_avg")
        read_95 = metrics.get("read_95")
        update_95 = metrics.get("update_95")

        if read_avg is None or update_avg is None:
            return None, None

        avg = 0.5 * read_avg + 0.5 * update_avg
        p95 = 0.5 * read_95 + 0.5 * update_95
        return avg, p95


    if workload == "b":
        read_avg = metrics.get("read_avg")
        update_avg = metrics.get("update_avg")
        read_95 = metrics.get("read_95")
        update_95 = metrics.get("update_95")

        if read_avg is None or update_avg is None:
            return None, None

        avg = 0.95 * read_avg + 0.05 * update_avg
        p95 = 0.95 * read_95 + 0.05 * update_95
        return avg, p95


    if workload == "c":
        avg = metrics.get("read_avg")
        p95 = metrics.get("read_95")
        return avg, p95

    return None, None




if __name__ == "__main__":
    results = load_all_results()
    df_stats = compute_statistics(results)

    print("\n=== GLOBAL STATS ===\n")
    print(df_stats)

    df_stats.to_csv("ycsb_stats.csv", index=False)
    print("\nStats saved in : ycsb_stats.csv")

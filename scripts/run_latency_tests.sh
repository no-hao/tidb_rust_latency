#!/bin/bash

LATENCIES=(0 100 200 500 1000)
HELPER_CONTAINER="alpine_helper"
TARGET_CONTAINER_IP="172.18.0.3" # TiKV IP
DURATION=300                     # 5 minutes per test

echo "Starting helper container..."
docker run --rm -d --name $HELPER_CONTAINER --network=tidb_rust_latency_tidb_network --privileged alpine sleep infinity
docker exec -it $HELPER_CONTAINER apk add --no-cache iproute2 iputils mysql-client

generate_load() {
  for i in {1..50}; do
    docker exec -i $HELPER_CONTAINER mysql -h tidb -P 4000 -u root <<EOF
CREATE DATABASE IF NOT EXISTS test;
USE test;
CREATE TABLE IF NOT EXISTS latency_test (id INT PRIMARY KEY, value VARCHAR(255));
INSERT INTO latency_test VALUES ($i, CONCAT('test_value_', $i)) ON DUPLICATE KEY UPDATE value=VALUES(value);
SELECT * FROM latency_test WHERE id = $i;
EOF
  done
}

for LATENCY in "${LATENCIES[@]}"; do
  echo "Applying ${LATENCY}ms latency to $TARGET_CONTAINER_IP"
  docker exec -it $HELPER_CONTAINER tc qdisc add dev eth0 root netem delay ${LATENCY}ms

  echo "Collecting metrics for latency ${LATENCY}ms..."
  start_time=$(date +%s)
  end_time=$((start_time + DURATION))

  while [ $(date +%s) -lt $end_time ]; do
    generate_load &
    sleep 10
  done

  TIMESTAMP=$(date +%s)
  curl -s "http://localhost:9090/api/v1/query?query=tikv_raftstore_propose_log_size_sum&time=${TIMESTAMP}" >"./metrics_${LATENCY}ms_${TIMESTAMP}_propose_log_size.json"
  curl -s "http://localhost:9090/api/v1/query?query=tikv_raftstore_raft_process_duration_secs_sum&time=${TIMESTAMP}" >"./metrics_${LATENCY}ms_${TIMESTAMP}_process_duration.json"
  curl -s "http://localhost:9090/api/v1/query?query=tikv_raftstore_leader_missing&time=${TIMESTAMP}" >"./metrics_${LATENCY}ms_${TIMESTAMP}_leader_missing.json"

  docker exec -it $HELPER_CONTAINER tc qdisc del dev eth0 root netem
  echo "Removed ${LATENCY}ms latency."
done

echo "Cleaning up..."
docker stop $HELPER_CONTAINER

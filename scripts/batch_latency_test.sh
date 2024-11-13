#!/bin/bash

# List of latency values to test (in ms)
LATENCIES=(0 100 200 500 1000) # You can add more values as needed
HELPER_CONTAINER="alpine_helper"
DURATION=300 # Duration of each test (5 minutes)

# List of container names or IDs to apply latency to
TARGET_CONTAINERS=(
  "tikv" # TiKV container name or ID
  "pd"   # PD container name or ID
  "tidb" # TiDB container name or ID
)

# Start helper container with necessary tools
echo "Starting helper container..."
docker run --rm -d --name $HELPER_CONTAINER --network=tidb_rust_latency_tidb_network --privileged alpine sleep infinity
docker exec -it $HELPER_CONTAINER apk add --no-cache iproute2 iputils mysql-client

# Function to generate load by inserting large batches of data
generate_load() {
  for i in {1..10}; do
    docker exec -i $HELPER_CONTAINER mysql -h tidb -P 4000 -u root <<EOF
CREATE DATABASE IF NOT EXISTS test;
USE test;
CREATE TABLE IF NOT EXISTS latency_test (
    id INT PRIMARY KEY,
    value VARCHAR(1024)
);
INSERT INTO latency_test (id, value) VALUES
($i * 10 + 1, REPEAT('a', 1024)),
($i * 10 + 2, REPEAT('b', 1024)),
($i * 10 + 3, REPEAT('c', 1024)),
($i * 10 + 4, REPEAT('d', 1024)),
($i * 10 + 5, REPEAT('e', 1024)),
($i * 10 + 6, REPEAT('f', 1024)),
($i * 10 + 7, REPEAT('g', 1024)),
($i * 10 + 8, REPEAT('h', 1024)),
($i * 10 + 9, REPEAT('i', 1024)),
($i * 10 + 10, REPEAT('j', 1024))
ON DUPLICATE KEY UPDATE value=VALUES(value);
EOF
  done
}

# Function to clean up the table after each test pass
cleanup_data() {
  docker exec -i $HELPER_CONTAINER mysql -h tidb -P 4000 -u root <<EOF
USE test;
DELETE FROM latency_test;
EOF
}

# Loop over each latency setting and run tests
for LATENCY in "${LATENCIES[@]}"; do
  echo "Applying ${LATENCY}ms latency to all target containers"

  # Apply latency to each target container's network interface using tc in the helper container
  for CONTAINER in "${TARGET_CONTAINERS[@]}"; do
    CONTAINER_PID=$(docker inspect --format '{{ .State.Pid }}' $CONTAINER)
    echo "Applying ${LATENCY}ms latency to $CONTAINER (PID: $CONTAINER_PID)"

    # Use nsenter to enter the network namespace of each container and apply tc netem on eth0
    docker exec -it $HELPER_CONTAINER nsenter --target $CONTAINER_PID --net tc qdisc add dev eth0 root netem delay ${LATENCY}ms
  done

  # Collect metrics for a duration (e.g., DURATION seconds)
  echo "Collecting metrics for latency ${LATENCY}ms..."
  start_time=$(date +%s)
  end_time=$((start_time + DURATION))

  while [ $(date +%s) -lt $end_time ]; do
    generate_load &
    sleep 10
  done

  # Save metrics snapshot from Prometheus (Raft-specific metrics)
  TIMESTAMP=$(date +%s)
  curl -s "http://localhost:9090/api/v1/query?query=tikv_raftstore_propose_log_size_sum&time=${TIMESTAMP}" >"./metrics_${LATENCY}ms_${TIMESTAMP}_propose_log_size.json"
  curl -s "http://localhost:9090/api/v1/query?query=tikv_raftstore_raft_process_duration_secs_sum&time=${TIMESTAMP}" >"./metrics_${LATENCY}ms_${TIMESTAMP}_process_duration.json"
  curl -s "http://localhost:9090/api/v1/query?query=tikv_raftstore_leader_missing&time=${TIMESTAMP}" >"./metrics_${LATENCY}ms_${TIMESTAMP}_leader_missing.json"

  # Remove latency from all target containers after each test pass and clean up data
  for CONTAINER in "${TARGET_CONTAINERS[@]}"; do
    CONTAINER_PID=$(docker inspect --format '{{ .State.Pid }}' $CONTAINER)
    echo "Removing ${LATENCY}ms latency from $CONTAINER (PID: $CONTAINER_PID)"

    # Use nsenter to enter the network namespace of each container and remove tc netem on eth0
    docker exec -it $HELPER_CONTAINER nsenter --target $CONTAINER_PID --net tc qdisc del dev eth0 root netem
  done

  cleanup_data

done

# Cleanup: Stop and remove the helper container
echo "Cleaning up..."
docker stop $HELPER_CONTAINER

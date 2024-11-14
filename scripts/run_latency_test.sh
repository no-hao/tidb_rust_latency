#!/bin/bash

# Default latency if not specified via command line
LATENCY=${1:-0}
HELPER_CONTAINER="alpine_helper"
DURATION=300                                  # Duration of test (5 minutes)
NETWORK_NAME="tidb_rust_latency_tidb_network" # Match your docker-compose network name

# Updated container names for 3-node TiKV setup
TARGET_CONTAINERS=(
  "tikv1"
  "tikv2"
  "tikv3"
  "pd"
  "tidb"
)

# Ensure the helper container is stopped if it exists
docker stop $HELPER_CONTAINER 2>/dev/null || true
docker rm $HELPER_CONTAINER 2>/dev/null || true

echo "Starting helper container..."
docker run --rm -d --name $HELPER_CONTAINER --network=$NETWORK_NAME --privileged alpine sleep infinity
docker exec $HELPER_CONTAINER apk add --no-cache iproute2 iputils mysql-client

# Enhanced load generation function to stress Raft consensus
generate_load() {
  local batch_size=100
  local value_size=4096 # 4KB per value to generate more substantial data

  # Create tables if they don't exist
  docker exec -i $HELPER_CONTAINER mysql -h tidb -P 4000 -u root <<EOF
CREATE DATABASE IF NOT EXISTS test;
USE test;
CREATE TABLE IF NOT EXISTS write_test (
    id INT PRIMARY KEY,
    value VARCHAR(4096)
);
CREATE TABLE IF NOT EXISTS read_test (
    id INT PRIMARY KEY,
    value VARCHAR(4096)
);
EOF

  # Generate write load
  for ((i = 1; i <= batch_size; i++)); do
    docker exec -i $HELPER_CONTAINER mysql -h tidb -P 4000 -u root <<EOF
USE test;
INSERT INTO write_test (id, value) 
VALUES ($i, REPEAT(CHAR(65 + ($i % 26)), $value_size))
ON DUPLICATE KEY UPDATE value=VALUES(value);
EOF
  done

  # Generate read load (mix of reads and writes to trigger Raft consensus)
  for ((i = 1; i <= batch_size; i++)); do
    docker exec -i $HELPER_CONTAINER mysql -h tidb -P 4000 -u root <<EOF
USE test;
SELECT * FROM write_test WHERE id = $i;
INSERT INTO read_test SELECT * FROM write_test WHERE id = $i;
EOF
  done
}

# Function to collect Raft-specific metrics
collect_metrics() {
  local timestamp=$1
  local metrics=(
    "tikv_raftstore_propose_log_size_sum"
    "tikv_raftstore_propose_log_size_count"
    "tikv_raftstore_raft_process_duration_secs_sum"
    "tikv_raftstore_raft_process_duration_secs_count"
    "tikv_raftstore_leader_missing"
    "tikv_raftstore_region_count"
    "tikv_raftstore_proposal_total"
    "tikv_raftstore_proposal_wait_duration_seconds_sum"
    "tikv_raftstore_proposal_wait_duration_seconds_count"
    "tikv_raftstore_apply_wait_duration_seconds_sum"
    "tikv_raftstore_apply_wait_duration_seconds_count"
  )

  mkdir -p "metrics_${LATENCY}ms"
  for metric in "${metrics[@]}"; do
    curl -s "http://localhost:9090/api/v1/query?query=${metric}&time=${timestamp}" \
      >"metrics_${LATENCY}ms/${metric}_${timestamp}.json"
  done
}

# Apply latency to all containers
echo "Applying ${LATENCY}ms latency to all containers..."
for CONTAINER in "${TARGET_CONTAINERS[@]}"; do
  echo "Applying latency to $CONTAINER..."
  # Get container's network interface
  CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' $CONTAINER)
  if [ -n "$CONTAINER_PID" ]; then
    docker exec $HELPER_CONTAINER nsenter -t $CONTAINER_PID -n tc qdisc add dev eth0 root netem delay ${LATENCY}ms
  else
    echo "Failed to get PID for container $CONTAINER"
    exit 1
  fi
done

# Run the test
echo "Running test with ${LATENCY}ms latency..."
start_time=$(date +%s)
end_time=$((start_time + DURATION))

# Collect initial metrics
collect_metrics $start_time

# Generate load while collecting metrics periodically
while [ $(date +%s) -lt $end_time ]; do
  generate_load &
  sleep 10

  # Collect metrics every minute
  if [ $(($(date +%s) % 60)) -eq 0 ]; then
    collect_metrics $(date +%s)
  fi
done

# Collect final metrics
collect_metrics $end_time

# Remove latency from all containers
echo "Removing latency from all containers..."
for CONTAINER in "${TARGET_CONTAINERS[@]}"; do
  echo "Removing latency from $CONTAINER..."
  CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' $CONTAINER)
  if [ -n "$CONTAINER_PID" ]; then
    docker exec $HELPER_CONTAINER nsenter -t $CONTAINER_PID -n tc qdisc del dev eth0 root
  fi
done

# Cleanup
echo "Cleaning up..."
docker exec -i $HELPER_CONTAINER mysql -h tidb -P 4000 -u root <<EOF
DROP DATABASE IF EXISTS test;
EOF
docker stop $HELPER_CONTAINER

echo "Test completed. Metrics saved in metrics_${LATENCY}ms/"

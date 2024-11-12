#!/bin/bash

# List of latency values to test (in ms)
LATENCIES=(0 100 200 500 1000)
HELPER_CONTAINER="alpine_helper" # Change this if the helper container is named differently
TARGET_CONTAINER_IP="172.18.0.2" # IP for the target container (e.g., PD or TiKV)

# Pull Alpine image and start the helper container with necessary tools
echo "Starting helper container..."
docker run --rm -d --name $HELPER_CONTAINER --network=tidb_rust_latency_tidb_network --privileged alpine sleep infinity
docker exec -it $HELPER_CONTAINER apk add --no-cache iproute2 iputils

# Loop over each latency setting
for LATENCY in "${LATENCIES[@]}"; do
  echo "Applying ${LATENCY}ms latency to $TARGET_CONTAINER_IP"

  # Add latency using tc command in the helper container
  docker exec -it $HELPER_CONTAINER tc qdisc add dev eth0 root netem delay ${LATENCY}ms

  # Collect metrics for a duration (e.g., 2 minutes)
  echo "Collecting metrics for latency ${LATENCY}ms..."
  sleep 120 # Adjust duration for stable metric collection

  # Save metrics snapshot from Prometheus
  TIMESTAMP=$(date +%s)
  curl -s "http://localhost:9090/api/v1/query?query=up&time=${TIMESTAMP}" >"./metrics_${LATENCY}ms_${TIMESTAMP}.json"

  # Remove latency
  docker exec -it $HELPER_CONTAINER tc qdisc del dev eth0 root netem
  echo "Removed ${LATENCY}ms latency."
done

# Cleanup: Stop and remove the helper container
echo "Cleaning up..."
docker stop $HELPER_CONTAINER

#!/bin/bash

LATENCY_MS=$1 # e.g., 100 for 100ms
PD_IP="172.19.0.3"
TIKV_IP="172.19.0.4"

# Enable packet filtering on macOS (required for pfctl)
sudo pfctl -E

# Clear existing rules and set up latency between specific IPs
sudo dnctl -f flush
sudo dnctl pipe 1 config delay ${LATENCY_MS}ms

# Apply latency rule between PD and TiKV
echo "dummynet out from $PD_IP to $TIKV_IP pipe 1" | sudo pfctl -f -

echo "Applied ${LATENCY_MS}ms latency between PD and TiKV."

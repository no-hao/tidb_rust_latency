#!/bin/bash

# Network partition test
iptables -A INPUT -p tcp --dport 20160 -j DROP
sleep 30
iptables -D INPUT -p tcp --dport 20160 -j DROP

# Leader election test
for container in tikv1 tikv2 tikv3; do
  docker pause $container
  sleep 10
  docker unpause $container
  sleep 20
done

# Clock skew test
for container in tikv1 tikv2 tikv3; do
  docker exec $container date -s "$(date -d '5 minutes ago')"
  sleep 10
  docker exec $container hwclock --hctosys
  sleep 20
done

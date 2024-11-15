#docker network inspect tidb_rust_latency_tidb_network Setup Guide for TiDB Latency Testing with Docker

This document provides step-by-step instructions for setting up and testing network latency in a Dockerized TiDB environment,
specifically for running Raft consensus experiments with latency applied between containers.

---

## Prerequisites

- **Docker**: Ensure Docker is installed and running on your system.
- **Docker Compose**: This setup assumes you have `docker-compose` installed and that you have defined containers like `pd`, `tikv`, `grafana`, and `prometheus` in `docker-compose.yml`.

---

## 1. Starting Containers with Docker Compose

### Command

note: may need to chmod scripts e.g. chmod +x run_latency_tests.sh

```bash
docker-compose up -d
```

- **Explanation**: This command starts all containers defined in your `docker-compose.yml` file in detached mode. This setup includes TiDB components such as `pd`, `tikv`, and any other services defined for the `tidb_rust_latency` experiment.

---

## 2. Checking Container Status

### Command

```bash
docker-compose ps
```

- **Explanation**: Lists all running containers along with their status and exposed ports. Verify that all required services are up and running before proceeding.

---

## 3. Getting IP Addresses of Containers

Each container will have a unique IP address within Docker’s internal network. To retrieve these IPs:

### Command

```bash
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container_name>
e.g.
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pd
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' tikv
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' tidb

```

Replace `<container_name>` with the names of each container (e.g., `pd`, `tikv`, `tidb`).

- **Explanation**: This command provides the IP address for a specific container. Record these IPs for applying latency rules and testing network behavior.

---

## 4. Applying Latency Using a Helper Container

To simulate network latency between containers:

### 4.1. Start a Helper Container

Run a helper Alpine container in privileged mode, connecting it to the `tidb_rust_latency_tidb_network` to manage network settings.

```bash
docker run --rm -it --privileged --network=tidb_rust_latency_tidb_network alpine /bin/sh
```

- **Explanation**: This command runs an Alpine container with access to network configuration commands. `--privileged` allows modification of network settings, and `--network=tidb_rust_latency_tidb_network` connects it to the correct Docker network.

### 4.2. Install Necessary Tools in Helper Container

Inside the helper container, install `iproute2` to get access to the `tc` command:
also install `iputils` if you want to test single delay injection for confirmation.

## e.g.

install iputils

```sh
apk add iproute2 iputils
tc qdisc add dev INTERFACE root netem delay 100ms
ping -c 5 TARGET_IP
```

inject delay

```sh
apk add iproute2 iputils
tc qdisc add dev INTERFACE root netem delay 100ms
ping -c 5 TARGET_IP
```

ping target ip

```sh
apk add iproute2 iputils
tc qdisc add dev INTERFACE root netem delay 100ms
ping -c 5 TARGET_IP
```

remove the delay

```sh
tc qdisc del dev INTERFACE root netem
```

---

```sh
apk add iproute2
```

- **Explanation**: `iproute2` includes the `tc` tool, which we’ll use to introduce network latency.

### 4.3. Apply Latency Between Containers

To introduce a 100ms latency, use `tc` to add delay on the interface (`eth0`):

```sh
tc qdisc add dev eth0 root netem delay 100ms
```

- **Explanation**: This command applies a 100ms delay to all outgoing packets on `eth0`, simulating latency between containers.

### 4.4. Testing Latency

With latency applied, you can test network delay by pinging the IP addresses of other containers from within the helper container.

```sh
ping -c 5 <target_container_ip>
```

- **Explanation**: Replace `<target_container_ip>` with the IP of another container (e.g., `tikv` or `pd`). The `ping` response time should reflect the applied 100ms delay.

---

## 5. Removing Latency

To remove the network delay:

### Command

```sh
tc qdisc del dev eth0 root netem
```

- **Explanation**: This command removes any network delays applied to `eth0`, restoring normal network conditions between containers.

---

## Notes

- **Helper Container**: The helper container used for setting latency is temporary. Use it only to apply and test latency, then exit.
- **IP Retrieval**: Ensure IP addresses are correct each time, as they may change upon restarting containers.

---

By following this guide, you should be able to recreate, modify, and remove latency settings as needed for your TiDB Raft consensus experiments.

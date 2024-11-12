# TiDB Raft Consensus Experiment Guide

## Prerequisites

- **Docker**: Ensure Docker is installed and running on your system.
- **Docker Compose**: This setup assumes you have `docker-compose` installed and that you have defined containers like `pd`, `tikv`, `grafana`, and `prometheus` in `docker-compose.yml`.

## 1. Starting Containers with Docker Compose

### Command:

```bash
docker-compose up -d
```

**Explanation**: This command starts all containers defined in your `docker-compose.yml` file in detached mode. This setup includes TiDB components such as `pd`, `tikv`, and any other services defined for the `tidb_rust_latency` experiment.

## 2. Checking Container Status

### Command:

```bash
docker-compose ps
```

**Explanation**: Lists all running containers along with their status and exposed ports. Verify that all required services are up and running before proceeding.

## 3. Getting IP Addresses of Containers

Each container will have a unique IP address within Docker’s internal network. To retrieve these IPs:

### Command:

```bash
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' <container_name>
```

For example:

```bash
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pd
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' tikv
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' tidb
```

**Explanation**: This command provides the IP address for a specific container. Record these IPs for applying latency rules and testing network behavior.

## 4. Applying Latency Using a Helper Container

To simulate network latency between containers:

### 4.1 Start a Helper Container

Run a helper Alpine container in privileged mode, connecting it to the `tidb_rust_latency_tidb_network` to manage network settings.

```bash
docker run --rm -it --privileged --network=tidb_rust_latency_tidb_network alpine /bin/sh
```

**Explanation**: This command runs an Alpine container with access to network configuration commands. The `--privileged` flag allows modification of network settings, and `--network=tidb_rust_latency_tidb_network` connects it to the correct Docker network.

### 4.2 Install Necessary Tools in Helper Container

Inside the helper container, install `iproute2` to get access to the `tc` command, which allows you to introduce latency.

```bash
apk add iproute2 iputils
```

**Explanation**: The `iproute2` package includes the `tc` tool, which we’ll use to introduce network latency.

### 4.3 Apply Latency Between Containers

To introduce a 100ms latency, use the `tc` command to add delay on the interface (eth0):

```bash
tc qdisc add dev eth0 root netem delay 100ms
```

**Explanation**: This command applies a 100ms delay to all outgoing packets on `eth0`, simulating latency between containers.

### 4.4 Testing Latency

With latency applied, you can test network delay by pinging the IP addresses of other containers from within the helper container.

```bash
ping -c 5 <target_container_ip>
```

**Explanation**: Replace `<target_container_ip>` with the IP of another container (e.g., `tikv`, or `pd`). The ping response time should reflect the applied 100ms delay.

## 5. Removing Latency

To remove the network delay:

### Command:

```bash
tc qdisc del dev eth0 root netem
```

**Explanation**: This command removes any network delays applied to `eth0`, restoring normal network conditions between containers.

## 6. Verifying Metrics Collection via Prometheus

You can verify that Prometheus is successfully scraping metrics from TiDB and TiKV by using `curl` from within a helper container or directly from your host machine:

### Example Commands:

#### From within a helper container:

```bash
docker run --rm -it --network=tidb_rust_latency_tidb_network alpine /bin/sh
apk add curl iputils

# Test connectivity to TiKV's metrics endpoint:
curl http://tikv:20180/metrics

# Test connectivity to TiDB's metrics endpoint:
curl http://tidb:10080/metrics

# Test connectivity to PD's client port (for completeness):
curl http://pd:2379/metrics
```

#### From your host machine (if ports are exposed):

```bash
curl http://localhost:<exposed_port>/metrics
```

## 7. Troubleshooting Tips

- **Container Logs**: If something isn't working as expected, check the logs for each service:

  ```bash
  docker logs pd
  docker logs tikv
  docker logs tidb
  ```

- **Helper Container for Testing Connectivity**: You can use an Alpine helper container connected to your Docker network for testing connectivity between containers using tools like `ping` or `curl`.

- **Restarting Services**: If changes are made to configuration files or services are not behaving as expected, restart all services using:
  ```bash
  docker-compose down && docker-compose up -d
  ```

### Notes

- The helper container used for setting latency is temporary. Use it only to apply and test latency, then exit.
- Ensure IP addresses are correct each time, as they may change upon restarting containers.

---

By following this guide, you should be able to recreate, modify, and remove latency settings as needed for your TiDB Raft consensus experiments.

# Signoz-Lite-Proxmox

[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange?style=flat-square&logo=proxmox)](https://www.proxmox.com)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?style=flat-square&logo=docker)](https://www.docker.com)
[![SigNoz](https://img.shields.io/badge/SigNoz-v0.122.0-blueviolet?style=flat-square)](https://signoz.io)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-Protocol-blue?style=flat-square&logo=opentelemetry)](https://opentelemetry.io)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-25.5.6-yellow?style=flat-square&logo=clickhouse)](https://clickhouse.com)

A compact SigNoz deployment for Proxmox or a small Ubuntu VM. It runs SigNoz, ClickHouse, ZooKeeper, the SigNoz OpenTelemetry Collector, and Caddy with internal HTTPS and basic auth.

## Requirements

| Resource | Minimum |
| :--- | :--- |
| CPU | 2 vCPU |
| RAM | 3GB minimum, 4GB recommended |
| Disk | 40GB+ SSD |
| OS | Ubuntu 22.04/24.04 |
| Swap | 4GB, created by `setup.sh` |

## Ports

| Port | Purpose |
| :--- | :--- |
| 22 | SSH |
| 80 | HTTP redirect / Caddy |
| 443 | SigNoz UI over HTTPS |
| 4317 | OTLP gRPC |
| 4318 | OTLP HTTP/protobuf |

## Deploy

Clone the repository on the server:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/jotyprokash/Signoz-Lite-Proxmox.git
cd Signoz-Lite-Proxmox
```

Run the setup script:

```bash
chmod +x setup.sh
sudo ./setup.sh
```

The script asks for:

| Prompt | Example |
| :--- | :--- |
| Internal Domain | `monitor.infra.internal` |
| Admin Password | password for Caddy basic auth |

If the script says Docker group access changed, apply it in the same shell:

```bash
newgrp docker
```

Start the stack:

```bash
docker compose up -d
```

First startup usually takes 1-3 minutes because ClickHouse starts, the telemetry migrator creates all schema tables, and then SigNoz/collector start.

## DNS

For an internal-only domain, every machine that opens the dashboard or sends telemetry must resolve the domain to the server IP.

On Linux/macOS clients:

```bash
echo "192.168.1.17 monitor.infra.internal" | sudo tee -a /etc/hosts
```

Replace `192.168.1.17` and `monitor.infra.internal` with your server IP and chosen domain.

## Access

Open:

```text
https://monitor.infra.internal
```

Caddy basic auth:

```text
Username: admin
Password: the Admin Password entered during setup.sh
```

The browser may show a certificate warning because this stack uses Caddy internal certificates. That is expected for an internal domain unless you install/trust the Caddy local CA certificate on your client machines.

Inside SigNoz, create the first workspace admin account from the UI. SigNoz requires a strong password for that app account.

## Verify

Check containers:

```bash
docker ps
docker ps -a | grep signoz-telemetrystore-migrator
```

Expected:

```text
signoz-zookeeper-1             healthy
signoz-clickhouse              healthy
signoz-telemetrystore-migrator Exited (0)
signoz-unified                 Up
signoz-otel-collector          Up
signoz-proxy                   Up
```

Check ClickHouse schema:

```bash
docker exec signoz-clickhouse clickhouse-client --query "SHOW TABLES FROM signoz_traces"
docker exec signoz-clickhouse clickhouse-client --query "SHOW TABLES FROM signoz_logs"
docker exec signoz-clickhouse clickhouse-client --query "SHOW TABLES FROM signoz_metrics"
```

Each command should return table names. If the table lists are empty, the telemetry migrator did not complete.

Check collector endpoints:

```bash
sudo apt-get install -y nmap
nmap -p 4317,4318 monitor.infra.internal
```

Expected:

```text
4317/tcp open
4318/tcp open
```

## OTEL Endpoints

Give developers one of these endpoints:

For OTLP HTTP/protobuf:

```bash
export OTEL_SERVICE_NAME=my-service
export OTEL_EXPORTER_OTLP_ENDPOINT=http://monitor.infra.internal:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

For OTLP gRPC:

```bash
export OTEL_SERVICE_NAME=my-service
export OTEL_EXPORTER_OTLP_ENDPOINT=http://monitor.infra.internal:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

Use `http://` for the collector endpoints in this stack. Caddy protects only the dashboard on ports 80/443; the OTEL collector listens directly on 4317/4318.

## Common Fixes

If `docker ps` says permission denied after running setup:

```bash
newgrp docker
```

Or log out and log back in.

If the dashboard opens but Traces/Logs show `failed to get tbl statement`, check the migrator:

```bash
docker ps -a | grep signoz-telemetrystore-migrator
docker logs --tail 120 signoz-telemetrystore-migrator
```

The migrator must show `Exited (0)`.

If you need a clean ClickHouse re-initialization:

```bash
docker compose down
mv data/clickhouse data/clickhouse.bak.$(date +%Y%m%d-%H%M%S)
mkdir -p data/clickhouse
docker compose up -d
```

Only do this when you are okay starting ClickHouse telemetry storage fresh.

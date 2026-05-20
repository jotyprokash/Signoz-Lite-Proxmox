# Signoz-Lite-Proxmox

[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange?style=flat-square&logo=proxmox)](https://www.proxmox.com)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?style=flat-square&logo=docker)](https://www.docker.com)
[![SigNoz](https://img.shields.io/badge/SigNoz-v0.122.0-blueviolet?style=flat-square)](https://signoz.io)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-Protocol-blue?style=flat-square&logo=opentelemetry)](https://opentelemetry.io)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-25.5.6-yellow?style=flat-square&logo=clickhouse)](https://clickhouse.com)

A compact SigNoz deployment for Proxmox or a small Ubuntu VM. It runs SigNoz, ClickHouse, ZooKeeper, the SigNoz OpenTelemetry Collector, and Caddy with internal HTTPS and basic auth.

## Architecture

![SigNoz Proxmox production observability architecture](assets/signoz-production-architecture.png)

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

## Cloudflare Tunnel With A Namecheap Domain

Use this when the VM is behind Proxmox/home NAT and you want `https://signoz.example.com` without exposing your public IP.

Recommended public layout:

| Hostname | Cloudflare Tunnel service | Notes |
| :--- | :--- | :--- |
| `signoz.example.com` | `https://caddy:443` | SigNoz UI through existing Caddy basic auth |
| `otel.example.com` | `http://otel-collector:4318` | Optional OTLP HTTP/protobuf ingestion |

Keep OTLP gRPC on `4317` private unless you are using Cloudflare private network routing/WARP. Cloudflare public hostname routing is the clean fit for the dashboard and OTLP HTTP on `4318`; it is not the right default for public OTLP gRPC.

### 1. Move Namecheap DNS To Cloudflare

1. Add the domain to Cloudflare.
2. Cloudflare will show two nameservers.
3. In Namecheap, set the domain's nameservers to the Cloudflare nameservers.
4. Wait until Cloudflare marks the zone active.

Do not create `A` records pointing to your home/public IP for this stack. The tunnel creates Cloudflare-managed DNS records that point to the tunnel instead.

### 2. Create The Tunnel

In Cloudflare Zero Trust:

1. Go to **Networks** -> **Tunnels**.
2. Create a Cloudflared tunnel.
3. Choose Docker as the connector environment.
4. Copy the tunnel token.

Add the token to `.env` on the server:

```bash
printf '\nCLOUDFLARED_TOKEN=%s\n' 'paste-your-cloudflare-tunnel-token-here' >> .env
```

Set your public dashboard domain in `.env`:

```bash
SIGNOZ_DOMAIN=signoz.example.com
```

Replace `signoz.example.com` with your real subdomain.

### 3. Route The Public Hostnames

In the tunnel's **Public Hostnames** settings, add:

| Subdomain | Domain | Type | URL | Extra setting |
| :--- | :--- | :--- | :--- | :--- |
| `signoz` | `example.com` | `HTTPS` | `caddy:443` | Enable **No TLS Verify** |

`No TLS Verify` is needed because this repo's Caddy config uses an internal Caddy certificate between `cloudflared` and Caddy. The browser still gets a normal Cloudflare-managed public certificate at the edge.

Optional OTLP HTTP ingestion:

| Subdomain | Domain | Type | URL |
| :--- | :--- | :--- | :--- |
| `otel` | `example.com` | `HTTP` | `otel-collector:4318` |

If you expose `otel.example.com`, protect it with Cloudflare Access service tokens or keep it restricted to known clients. Telemetry endpoints are write endpoints; leaving them open invites noise and storage growth.

### 4. Start With Tunnel Enabled

```bash
docker compose --profile cloudflare up -d
```

Verify:

```bash
docker ps
docker logs --tail 100 signoz-cloudflared
```

Open:

```text
https://signoz.example.com
```

You should see Caddy basic auth first, then SigNoz login.

### 5. Lock Down The VM

Cloudflare Tunnel makes outbound connections from the VM, so your router does not need inbound port forwards for `80`, `443`, `4317`, or `4318`.

For a tunnel-only deployment:

```bash
sudo ufw delete allow 80/tcp
sudo ufw delete allow 443/tcp
sudo ufw delete allow 4317/tcp
sudo ufw delete allow 4318/tcp
sudo ufw allow 22/tcp
sudo ufw reload
```

Also remove any router port forwarding rules to this VM. If SSH should not be reachable from the internet, keep `22` allowed only from your LAN, VPN, or management IP.

### 6. Public OTLP HTTP Client Example

For OTLP HTTP/protobuf through Cloudflare Tunnel:

```bash
export OTEL_SERVICE_NAME=my-service
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.example.com
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

If you protect `otel.example.com` with a Cloudflare Access service token, pass the token headers from your OpenTelemetry SDK/exporter:

```bash
export OTEL_EXPORTER_OTLP_HEADERS='CF-Access-Client-Id=your-client-id,CF-Access-Client-Secret=your-client-secret'
```

For local/LAN clients, the existing direct endpoints still work:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://monitor.infra.internal:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

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

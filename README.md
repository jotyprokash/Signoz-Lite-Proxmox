# Signoz-Lite-Proxmox

[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange?style=flat-square&logo=proxmox)](https://www.proxmox.com)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?style=flat-square&logo=docker)](https://www.docker.com)
[![SigNoz](https://img.shields.io/badge/SigNoz-v0.122.0-blueviolet?style=flat-square)](https://signoz.io)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-Protocol-blue?style=flat-square&logo=opentelemetry)](https://opentelemetry.io)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-25.5.6-yellow?style=flat-square&logo=clickhouse)](https://clickhouse.com)

A compact SigNoz deployment for a Proxmox-hosted Ubuntu VM. It runs SigNoz, ClickHouse, ZooKeeper, the SigNoz OpenTelemetry Collector, Caddy, and optional Cloudflare Tunnel.

The production-friendly model is:

- public dashboard through Cloudflare Tunnel
- private EC2 telemetry over Tailscale to OTLP `4317`
- no public exposure for OTLP `4317` or `4318`
- Caddy basic auth in front of the SigNoz UI

## Architecture

![SigNoz Proxmox production observability architecture](assets/signoz-production-architecture.png)

## Deployment Modes

| Mode | Dashboard | OTLP ingestion | Use case |
| :--- | :--- | :--- | :--- |
| Internal-only | Internal DNS / hosts entry | Localhost or LAN bind | Lab or private LAN |
| Public dashboard | Cloudflare Tunnel | Private only | Access SigNoz UI from the internet without exposing origin IP |
| EC2 telemetry | Cloudflare Tunnel | Tailscale private IP | AWS EC2 apps export telemetry securely to on-prem Proxmox |

The recommended production path is **Public dashboard + EC2 telemetry**.

## Requirements

| Resource | Minimum |
| :--- | :--- |
| CPU | 2 vCPU |
| RAM | 3GB minimum, 4GB recommended |
| Disk | 40GB+ SSD |
| OS | Ubuntu 22.04/24.04 |
| Swap | 4GB, created by `setup.sh` |

Required tools on the VM:

- Docker / Docker Compose
- UFW
- curl
- openssl

`setup.sh` installs these on Ubuntu.

## Ports

| Port | Default exposure | Purpose |
| :--- | :--- | :--- |
| 22 | Host firewall allowed | SSH |
| 80 | Host firewall allowed by setup | Caddy HTTP redirect / local access |
| 443 | Host firewall allowed by setup | Caddy HTTPS / local access |
| 4317 | Denied by UFW, bound to `127.0.0.1` by default | OTLP gRPC |
| 4318 | Denied by UFW, bound to `127.0.0.1` by default | OTLP HTTP/protobuf |

For Cloudflare Tunnel-only deployments, your router does not need inbound forwards for `80`, `443`, `4317`, or `4318`.

## Quick Start

Clone the repository on the Proxmox VM:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/jotyprokash/Signoz-Lite-Proxmox.git
cd Signoz-Lite-Proxmox
```

Run setup:

```bash
chmod +x setup.sh
sudo ./setup.sh
```

Prompts:

| Prompt | Example |
| :--- | :--- |
| Dashboard Domain | `monitor.infra.internal` or `signoz.example.com` |
| Admin Password | Password for Caddy basic auth |

If Docker group access changed, apply it in the same shell:

```bash
newgrp docker
```

Start internal-only mode:

```bash
docker compose up -d
```

First startup usually takes 1-3 minutes while ClickHouse starts and the telemetry migrator creates schema tables.

## Environment

`setup.sh` creates `.env`. A documented template is available in `.env.example`.

Important variables:

| Variable | Purpose |
| :--- | :--- |
| `SIGNOZ_DOMAIN` | Dashboard hostname used by Caddy |
| `SIGNOZ_ADMIN_PASSWORD_HASH` | Caddy basic auth password hash |
| `SIGNOZ_TOKENIZER_JWT_SECRET` | SigNoz JWT secret |
| `CLOUDFLARED_TOKEN` | Cloudflare Tunnel token |
| `OTEL_GRPC_BIND` | Host IP to bind OTLP gRPC `4317` |
| `OTEL_HTTP_BIND` | Host IP to bind OTLP HTTP `4318` |

OTLP binds are safe by default:

```env
OTEL_GRPC_BIND=127.0.0.1
OTEL_HTTP_BIND=127.0.0.1
```

For EC2 telemetry over Tailscale, set both to the Proxmox VM Tailscale IP:

```env
OTEL_GRPC_BIND=100.x.x.x
OTEL_HTTP_BIND=100.x.x.x
```

## Internal-Only Access

For an internal-only dashboard, every client that opens SigNoz must resolve the dashboard domain to the VM IP.

Example Linux/macOS hosts entry:

```bash
echo "192.168.1.17 monitor.infra.internal" | sudo tee -a /etc/hosts
```

Open:

```text
https://monitor.infra.internal
```

Caddy basic auth:

```text
Username: admin
Password: the Admin Password entered during setup.sh
```

The browser may show a certificate warning because this stack uses Caddy internal certificates. That is expected unless you trust the Caddy local CA on your clients.

## Secure Public Dashboard With Cloudflare Tunnel

Use this when the VM is behind Proxmox/home NAT and you want `https://signoz.example.com` without exposing your public IP.

### 1. Move Namecheap DNS To Cloudflare

1. Add the domain to Cloudflare.
2. Cloudflare will show two nameservers.
3. In Namecheap, set the domain's nameservers to the Cloudflare nameservers.
4. Wait until Cloudflare marks the zone active.

Do not create `A` records pointing to your home/public IP for this stack. The tunnel creates Cloudflare-managed DNS records that point to Cloudflare instead.

### 2. Create The Tunnel

In Cloudflare Zero Trust:

1. Go to **Networks** -> **Tunnels**.
2. Create a Cloudflared tunnel.
3. Choose Docker as the connector environment.
4. Copy the tunnel token.

Add the token to `.env`:

```bash
printf '\nCLOUDFLARED_TOKEN=%s\n' 'paste-your-cloudflare-tunnel-token-here' >> .env
```

Set your public dashboard hostname:

```env
SIGNOZ_DOMAIN=signoz.example.com
```

### 3. Route The Public Hostname

In the tunnel's **Public Hostnames** settings:

| Subdomain | Domain | Type | URL | Extra setting |
| :--- | :--- | :--- | :--- | :--- |
| `signoz` | `example.com` | `HTTPS` | `caddy:443` | Enable **No TLS Verify** |

`No TLS Verify` is needed because this repo uses Caddy internal TLS between `cloudflared` and Caddy. The browser still receives a normal Cloudflare-managed public certificate at the edge.

Start with the tunnel profile:

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

You should see Caddy basic auth first, then the SigNoz login.

## Private EC2 Telemetry With Tailscale

This is the recommended way to send telemetry from AWS EC2 to the Proxmox VM without exposing OTLP to the public internet.

Install Tailscale on the Proxmox VM:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4
```

Suppose the Proxmox VM Tailscale IP is:

```text
100.90.12.34
```

Update `.env`:

```env
OTEL_GRPC_BIND=100.90.12.34
OTEL_HTTP_BIND=100.90.12.34
```

Restart the stack:

```bash
docker compose --profile cloudflare up -d
```

Lock OTLP to Tailscale at the host firewall:

```bash
sudo ufw insert 1 allow in on tailscale0 to any port 4317 proto tcp
sudo ufw insert 1 allow in on tailscale0 to any port 4318 proto tcp
sudo ufw deny 4317/tcp
sudo ufw deny 4318/tcp
sudo ufw reload
```

Install Tailscale on each EC2 instance or on a dedicated EC2 OpenTelemetry Collector:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale status
```

Configure EC2 applications to export telemetry to the Proxmox VM Tailscale IP:

```bash
export OTEL_SERVICE_NAME=my-service
export OTEL_EXPORTER_OTLP_ENDPOINT=http://100.90.12.34:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

For OTLP HTTP/protobuf:

```bash
export OTEL_SERVICE_NAME=my-service
export OTEL_EXPORTER_OTLP_ENDPOINT=http://100.90.12.34:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

Use the Tailscale IP for telemetry. Do not use the public dashboard domain for EC2 OTLP traffic.

For multiple EC2 instances, a cleaner production pattern is:

```text
EC2 apps -> AWS-side OpenTelemetry Collector -> Tailscale -> Proxmox SigNoz collector :4317
```

That way only one or a few AWS collector nodes need access to the Proxmox telemetry endpoint.

## Security Checklist

- Do not expose `4317` or `4318` publicly.
- Do not create public `otel.example.com` or `grpc.example.com` records for this deployment model.
- Do not create DNS `A` records pointing to your home/proxmox public IP.
- Remove router port forwards for `80`, `443`, `4317`, and `4318` when using Cloudflare Tunnel.
- Keep Caddy basic auth enabled.
- Consider Cloudflare Access in front of `signoz.example.com`.
- Restrict SSH to LAN, VPN, Tailscale, or a known management IP.

Expected scan posture:

```text
nmap signoz.example.com
  -> Cloudflare edge, HTTPS 443

nmap your-origin-public-ip
  -> no public 4317/4318
  -> no public 443 if Cloudflare Tunnel is the only public path
```

## Verify

Check containers:

```bash
docker compose ps
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

Check bound OTLP listeners on the VM:

```bash
ss -ltnp | grep -E ':4317|:4318'
```

For Tailscale mode, you should see the Proxmox Tailscale IP bound to `4317` and `4318`, not `0.0.0.0`.

From an EC2 instance joined to the same Tailscale network:

```bash
nc -vz 100.90.12.34 4317
nc -vz 100.90.12.34 4318
```

Check Cloudflare Tunnel:

```bash
docker logs --tail 100 signoz-cloudflared
curl -Ik https://signoz.example.com
```

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

If the Cloudflare Tunnel is not reachable:

```bash
docker logs --tail 100 signoz-cloudflared
docker compose --profile cloudflare up -d
```

Confirm the tunnel public hostname points to:

```text
https://caddy:443
```

with **No TLS Verify** enabled.

If EC2 cannot reach OTLP:

```bash
tailscale status
tailscale ping 100.90.12.34
nc -vz 100.90.12.34 4317
sudo ufw status numbered
```

Confirm `.env` contains the Proxmox VM Tailscale IP:

```env
OTEL_GRPC_BIND=100.90.12.34
OTEL_HTTP_BIND=100.90.12.34
```

If you need a clean ClickHouse re-initialization:

```bash
docker compose down
mv data/clickhouse data/clickhouse.bak.$(date +%Y%m%d-%H%M%S)
mkdir -p data/clickhouse
docker compose up -d
```

Only do this when you are okay starting ClickHouse telemetry storage fresh.

## Maintenance

Update containers:

```bash
docker compose pull
docker compose --profile cloudflare up -d
```

Check logs:

```bash
docker compose logs -f
docker logs --tail 100 signoz-otel-collector
docker logs --tail 100 signoz-unified
```

Check disk usage:

```bash
docker system df
du -sh data/*
```

Back up at minimum:

```text
.env
data/signoz
data/clickhouse
data/zookeeper
```

# Signoz-Lite-Proxmox

[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange?style=flat-square&logo=proxmox)](https://www.proxmox.com)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?style=flat-square&logo=docker)](https://www.docker.com)
[![SigNoz](https://img.shields.io/badge/SigNoz-v0.122.0-blueviolet?style=flat-square)](https://signoz.io)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-Protocol-blue?style=flat-square&logo=opentelemetry)](https://opentelemetry.io)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-25.5.6-yellow?style=flat-square&logo=clickhouse)](https://clickhouse.com)

A lightweight SigNoz deployment for a Proxmox-hosted Ubuntu VM, designed for public dashboard access through Cloudflare Tunnel and private telemetry ingestion from AWS EC2 over Tailscale.

## Architecture

![SigNoz Proxmox production observability architecture](assets/signoz-production-architecture.png)

## What This Deploys

- SigNoz `v0.122.0`
- SigNoz OpenTelemetry Collector `v0.144.3`
- ClickHouse `25.5.6`
- ZooKeeper
- Caddy with internal TLS and basic auth
- Optional Cloudflare Tunnel connector

## Secure Access Model

| Path | Route | Exposure |
| :--- | :--- | :--- |
| Dashboard | `signoz.example.com` -> Cloudflare Tunnel -> Caddy -> SigNoz | Public domain, origin IP hidden |
| EC2 telemetry | EC2 -> Tailscale -> Proxmox VM `:4317` | Private only |
| OTLP HTTP | Tailscale/LAN bind on `:4318` | Private only |
| Public OTLP | Not used | Closed |

OTLP ports bind to `127.0.0.1` by default. For EC2 telemetry, bind them to the Proxmox VM's Tailscale IP in `.env`.

## Quick Start

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/jotyprokash/Signoz-Lite-Proxmox.git
cd Signoz-Lite-Proxmox
chmod +x setup.sh
sudo ./setup.sh
```

Start internal-only mode:

```bash
docker compose up -d
```

Start with Cloudflare Tunnel enabled:

```bash
docker compose --profile cloudflare up -d
```

## Deployment Guide

For the full reproducible setup, including Namecheap/Cloudflare DNS, Cloudflare Tunnel, Tailscale-based EC2 telemetry, firewall rules, verification, and troubleshooting, see:

[docs/deployment.md](docs/deployment.md)

## Requirements

| Resource | Minimum |
| :--- | :--- |
| CPU | 2 vCPU |
| RAM | 3GB minimum, 4GB recommended |
| Disk | 40GB+ SSD |
| OS | Ubuntu 22.04/24.04 |
| Swap | 4GB, created by `setup.sh` |

## Configuration

`setup.sh` creates `.env`. Use [.env.example](.env.example) as the configuration reference.

Key production settings:

```env
SIGNOZ_DOMAIN=signoz.example.com
CLOUDFLARED_TOKEN=paste-cloudflare-tunnel-token
OTEL_GRPC_BIND=100.x.x.x
OTEL_HTTP_BIND=100.x.x.x
```

`100.x.x.x` should be the Proxmox VM's Tailscale IP.

## Security Notes

- Do not expose `4317` or `4318` publicly.
- Do not create public OTLP hostnames for this deployment model.
- Do not point DNS `A` records at your home/proxmox public IP.
- Remove router port forwards when using Cloudflare Tunnel.
- Keep Caddy basic auth enabled.

## Maintenance

Operational commands, verification steps, troubleshooting, and backup notes are in [docs/deployment.md](docs/deployment.md).

## EC2 App Onboarding

For API-only tracing without changing the app codebase, use the external runtime toolkit in [ec2-observability](ec2-observability/).

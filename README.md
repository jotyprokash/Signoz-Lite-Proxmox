# SigNoz Proxmox Deployment (Optimized)

[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange?style=flat-square&logo=proxmox)](https://www.proxmox.com)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?style=flat-square&logo=docker)](https://www.docker.com)
[![SigNoz](https://img.shields.io/badge/SigNoz-v0.41.0-blueviolet?style=flat-square)](https://signoz.io)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-Protocol-blue?style=flat-square&logo=opentelemetry)](https://opentelemetry.io)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-OLAP-yellow?style=flat-square&logo=clickhouse)](https://clickhouse.com)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E94333?style=flat-square&logo=ubuntu)](https://ubuntu.com)
[![Shell](https://img.shields.io/badge/Shell-Script-4EAA25?style=flat-square&logo=gnubash)](https://www.gnu.org/software/bash/)


A production-ready, resource-optimized deployment of SigNoz for Proxmox Virtual Environments. This configuration is specifically tuned to operate within a 2GB RAM constraint while providing internal HTTPS and basic authentication.

## Technical Overview

This repository provides a hardened SigNoz stack optimized for initial R&D and low-resource environments. It replaces the default high-memory configurations with a tiered resource-limiting strategy.

### Core Features

*   **Low-Resource Optimization**: Configured to run reliably on 2GB RAM using aggressive ClickHouse memory capping and a mandatory 4GB swap strategy.
*   **Internal HTTPS**: Automated SSL certificate management via Caddy's internal CA.
*   **Security Layer**: Integrated Basic Authentication and pre-configured UFW firewall rules.
*   **No Hardcoded Secrets**: Interactive setup script handles domain and credential configuration via environment variables.

## Architecture

*   **Host**: Proxmox VM (Ubuntu 24.04 recommended)
*   **Proxy**: Caddy (Internal HTTPS & Auth)
*   **Database**: ClickHouse (Single node, memory-limited)
*   **Collector**: OpenTelemetry (Memory-limited processing)
*   **Orchestration**: Docker Compose

## Deployment Instructions

### 1. Provision the VM
Ensure your Proxmox VM meets these minimum specifications:
*   CPU: 2 vCPUs
*   RAM: 2GB (Static)
*   Disk: 40GB+ SSD

### 2. Run the Setup Script
Transfer the repository files to the VM and execute the setup:
```bash
chmod +x setup.sh
sudo ./setup.sh
```
The script will:
1.  Install Docker and dependencies.
2.  Provision a 4GB swap file.
3.  Prompt for your internal domain and admin password.
4.  Generate secure bcrypt hashes for the proxy layer.
5.  Configure the UFW firewall.

### 3. Initialize the Stack
```bash
docker compose up -d
```

## Configuration Details

### Resource Limits
The stack enforces the following memory caps to prevent Out-Of-Memory (OOM) events:
*   **ClickHouse**: 1000MB
*   **Query Service**: 500MB
*   **OTEL Collector**: 200MB
*   **Caddy/AlertManager**: 100MB each

### Internal Domain Access
To access the dashboard from a local machine, add the VM IP to your hosts file:
```text
<VM_IP> your-chosen-domain.internal
```
Access the UI via `https://your-chosen-domain.internal`.

## Security Notice
Authentication is handled at the proxy level (Caddy). Credentials provided during setup are hashed and stored in a local `.env` file. Do not commit the generated `.env` file to version control.

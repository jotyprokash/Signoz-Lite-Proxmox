# Signoz-Lite-Proxmox

[![Proxmox](https://img.shields.io/badge/Proxmox-VE-orange?style=flat-square&logo=proxmox)](https://www.proxmox.com)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?style=flat-square&logo=docker)](https://www.docker.com)
[![SigNoz](https://img.shields.io/badge/SigNoz-v0.41.0-blueviolet?style=flat-square)](https://signoz.io)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-Protocol-blue?style=flat-square&logo=opentelemetry)](https://opentelemetry.io)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-OLAP-yellow?style=flat-square&logo=clickhouse)](https://clickhouse.com)

A resource-optimized SigNoz deployment for Proxmox VE, tuned for 2GB RAM environments with internal HTTPS and security hardening.

## Hardware Requirements
*   **CPU**: 2 vCPUs
*   **RAM**: 3GB minimum, 4GB recommended
*   **Disk**: 40GB+ SSD
*   **Swap**: 4GB (Provisioned by setup script)

## Deployment

1.  **Prepare Environment**:
    ```bash
    chmod +x setup.sh
    sudo ./setup.sh
    ```
    *Script handles Docker, Swap, Firewall, and SSL configuration.*

2.  **Start Stack**:
    ```bash
    docker compose up -d
    ```

3.  **Access**:
    Map VM IP to your domain in `/etc/hosts` and access via:
    `https://your-domain.internal`

## Resource Limits
| Service | Memory Limit |
| :--- | :--- |
| ClickHouse | 1000MB |
| Query Service | 500MB |
| OTel Collector | 200MB |
| Proxy (Caddy) | 100MB |
| ZooKeeper | shared host memory |

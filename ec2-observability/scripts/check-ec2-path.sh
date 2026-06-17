#!/usr/bin/env bash
set -euo pipefail

PROXMOX_OTLP_HOST="${PROXMOX_OTLP_HOST:-100.88.205.91}"
EC2_COLLECTOR="${EC2_COLLECTOR:-saafir-b2b-admin-panel-dev-otel-collector}"

echo "Tailscale IP:"
tailscale ip -4 || true

echo "Testing Proxmox OTLP ports:"
nc -vz "${PROXMOX_OTLP_HOST}" 4317
nc -vz "${PROXMOX_OTLP_HOST}" 4318

echo "Recent EC2 collector logs:"
docker logs --since 10m "${EC2_COLLECTOR}" || true


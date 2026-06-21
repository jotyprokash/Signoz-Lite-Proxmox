#!/usr/bin/env bash
set -euo pipefail

PROXMOX_OTLP_HOST="${PROXMOX_OTLP_HOST:?Set PROXMOX_OTLP_HOST to the private SigNoz collector address}"
PROXMOX_OTLP_GRPC_PORT="${PROXMOX_OTLP_GRPC_PORT:-4317}"
PROXMOX_OTLP_HTTP_PORT="${PROXMOX_OTLP_HTTP_PORT:-4318}"
EC2_COLLECTOR="${EC2_COLLECTOR:-}"

echo "Tailscale IP:"
tailscale ip -4 || true

echo "Testing Proxmox OTLP ports:"
nc -vz "${PROXMOX_OTLP_HOST}" "${PROXMOX_OTLP_GRPC_PORT}"
nc -vz "${PROXMOX_OTLP_HOST}" "${PROXMOX_OTLP_HTTP_PORT}"

if [[ -n "${EC2_COLLECTOR}" ]]; then
  echo "Recent EC2 collector logs:"
  docker logs --since 10m "${EC2_COLLECTOR}" || true
fi

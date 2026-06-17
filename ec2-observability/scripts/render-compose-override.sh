#!/usr/bin/env bash
set -euo pipefail

OUTPUT="/opt/saafir-observability/docker-compose.otel.yml"
NODE_AUTO_DIR="/opt/saafir-observability/node-auto"
COLLECTOR_ENDPOINT="http://otel-collector:4317"
ENVIRONMENT="development"
NAMESPACE="saafir"
SERVICES=()

usage() {
  cat <<'EOF'
Usage:
  render-compose-override.sh [options] --service compose_service=otel_service_name

Options:
  --output PATH                 Output compose override path.
  --node-auto-dir PATH          Host path mounted into containers as /otel-node.
  --collector-endpoint URL      Local EC2 collector endpoint from app containers.
  --environment NAME            deployment.environment value.
  --namespace NAME              service.namespace value.
  --service NAME=SERVICE_NAME   Compose service and OTel service name. Repeatable.

Example:
  sudo ./scripts/render-compose-override.sh \
    --service api=saafir-dev-api \
    --service auth=saafir-dev-auth
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --node-auto-dir)
      NODE_AUTO_DIR="$2"
      shift 2
      ;;
    --collector-endpoint)
      COLLECTOR_ENDPOINT="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --service)
      SERVICES+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "At least one --service compose_service=otel_service_name is required." >&2
  usage >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"

{
  echo "services:"
  for item in "${SERVICES[@]}"; do
    if [[ "${item}" != *=* ]]; then
      echo "Invalid --service value '${item}'. Expected compose_service=otel_service_name." >&2
      exit 1
    fi

    compose_service="${item%%=*}"
    otel_service="${item#*=}"

    cat <<EOF
  ${compose_service}:
    environment:
      NODE_OPTIONS: --require /otel-node/otel-bootstrap.js
      OTEL_SERVICE_NAME: ${otel_service}
      OTEL_SERVICE_NAMESPACE: ${NAMESPACE}
      OTEL_DEPLOYMENT_ENVIRONMENT: ${ENVIRONMENT}
      OTEL_EXPORTER_OTLP_ENDPOINT: ${COLLECTOR_ENDPOINT}
      OTEL_EXPORTER_OTLP_PROTOCOL: grpc
      OTEL_RESOURCE_ATTRIBUTES: deployment.environment=${ENVIRONMENT},service.namespace=${NAMESPACE},service.type=api,host.type=ec2,cloud.provider=aws
    volumes:
      - ${NODE_AUTO_DIR}:/otel-node:ro
EOF
  done
} > "${OUTPUT}"

echo "Wrote ${OUTPUT}"


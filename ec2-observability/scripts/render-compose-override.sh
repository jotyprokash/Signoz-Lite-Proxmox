#!/usr/bin/env bash
set -euo pipefail

OUTPUT="/opt/signoz-ec2-observability/docker-compose.otel.yml"
NODE_AUTO_DIR="/opt/signoz-ec2-observability/node-auto"
COLLECTOR_ENDPOINT="http://otel-collector:4317"
ENVIRONMENT="development"
NAMESPACE="application"
COLLECTOR_CONFIG="/opt/signoz-ec2-observability/collector/config.yml"
COLLECTOR_IMAGE="otel/opentelemetry-collector-contrib:0.128.0"
APP_NETWORK="application-network"
SAMPLE_RATIO="0.10"
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
  --collector-config PATH       Host path to the EC2 collector configuration.
  --collector-image IMAGE      Pinned EC2 collector image.
  --app-network NAME           Existing application Compose network.
  --sample-ratio RATIO         Head-sampling ratio from 0 through 1.
  --service NAME=SERVICE_NAME   Compose service and OTel service name. Repeatable.

Example:
  sudo ./scripts/render-compose-override.sh \
    --service web=example-web \
    --service worker=example-worker
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
    --collector-config)
      COLLECTOR_CONFIG="$2"
      shift 2
      ;;
    --collector-image)
      COLLECTOR_IMAGE="$2"
      shift 2
      ;;
    --sample-ratio)
      SAMPLE_RATIO="$2"
      shift 2
      ;;
    --app-network)
      APP_NETWORK="$2"
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

if [[ ! -f "${NODE_AUTO_DIR}/otel-bootstrap.js" || ! -d "${NODE_AUTO_DIR}/node_modules" ]]; then
  echo "OpenTelemetry node-auto bundle is not installed at ${NODE_AUTO_DIR}." >&2
  echo "Run install-node-auto.sh before rendering/applying the compose override." >&2
  exit 1
fi

if [[ ! -f "${COLLECTOR_CONFIG}" ]]; then
  echo "Collector configuration does not exist at ${COLLECTOR_CONFIG}." >&2
  exit 1
fi

if ! [[ "${SAMPLE_RATIO}" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; then
  echo "Invalid --sample-ratio '${SAMPLE_RATIO}'. Expected a value from 0 through 1." >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"

{
  echo "services:"
  cat <<EOF
  otel-collector:
    image: ${COLLECTOR_IMAGE}
    container_name: \${COMPOSE_PROJECT_NAME}-otel-collector
    command: ["--config=/etc/otelcol-contrib/config.yml"]
    restart: unless-stopped
    ports:
      - "127.0.0.1:4317:4317"
      - "127.0.0.1:4318:4318"
      - "127.0.0.1:13133:13133"
    volumes:
      - ${COLLECTOR_CONFIG}:/etc/otelcol-contrib/config.yml:ro
    networks:
      - ${APP_NETWORK}
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 384M
EOF
  for item in "${SERVICES[@]}"; do
    if [[ "${item}" != *=* ]]; then
      echo "Invalid --service value '${item}'. Expected compose_service=otel_service_name." >&2
      exit 1
    fi

    compose_service="${item%%=*}"
    otel_service="${item#*=}"

    if ! [[ "${compose_service}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
      echo "Invalid Compose service name '${compose_service}'." >&2
      exit 1
    fi
    if ! [[ "${otel_service}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
      echo "Invalid OpenTelemetry service name '${otel_service}'." >&2
      exit 1
    fi

    cat <<EOF
  ${compose_service}:
    environment:
      NODE_OPTIONS: --require /otel-node/otel-bootstrap.js
      OTEL_SERVICE_NAME: ${otel_service}
      OTEL_SERVICE_NAMESPACE: ${NAMESPACE}
      OTEL_DEPLOYMENT_ENVIRONMENT: ${ENVIRONMENT}
      OTEL_EXPORTER_OTLP_ENDPOINT: ${COLLECTOR_ENDPOINT}
      OTEL_EXPORTER_OTLP_PROTOCOL: grpc
      OTEL_NODE_IGNORED_PATHS: /health,/ready,/live,/metrics
      OTEL_TRACES_SAMPLER: parentbased_traceidratio
      OTEL_TRACES_SAMPLER_ARG: "${SAMPLE_RATIO}"
      OTEL_RESOURCE_ATTRIBUTES: deployment.environment.name=${ENVIRONMENT},deployment.environment=${ENVIRONMENT},service.namespace=${NAMESPACE},service.type=api,host.type=ec2,cloud.provider=aws
    volumes:
      - ${NODE_AUTO_DIR}:/otel-node:ro
EOF
  done
} > "${OUTPUT}"

echo "Wrote ${OUTPUT}"

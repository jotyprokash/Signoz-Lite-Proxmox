#!/usr/bin/env bash
set -euo pipefail

OUTPUT="/opt/signoz-ec2-observability/docker-compose.otel.yml"
NODE_AUTO_DIR="/opt/signoz-ec2-observability/node-auto"
COLLECTOR_ENDPOINT="http://otel-collector:4317"
ENVIRONMENT="development"
NAMESPACE="application"
COLLECTOR_CONFIG="/opt/signoz-ec2-observability/collector/config.yml"
COLLECTOR_CONFIG_VERSION="unversioned"
COLLECTOR_IMAGE="otel/opentelemetry-collector-contrib:0.153.0"
APP_NETWORK="application-network"
SAMPLE_RATIO="0.10"
IGNORED_PATHS="/health,/ready,/live,/metrics"
BUNDLE_VERSION="unversioned"
ENABLE_DOCKER_LOGS="false"
DOCKER_LOG_MAX_SIZE="20m"
DOCKER_LOG_MAX_FILES="3"
DOCKER_SOCKET_PROXY_IMAGE="ghcr.io/tecnativa/docker-socket-proxy:v0.4.2"
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
  --collector-config-version    Collector config hash used for recreation.
  --collector-image IMAGE      Pinned EC2 collector image.
  --app-network NAME           Existing application Compose network.
  --sample-ratio RATIO         Head-sampling ratio from 0 through 1.
  --ignored-paths PATHS        Comma-separated incoming HTTP paths to exclude.
  --bundle-version HASH        Instrumentation content hash used for recreation.
  --enable-docker-logs BOOL    Collect Docker stdout/stderr logs through the collector.
  --docker-log-max-size SIZE   Rotate each Docker json-file at this size.
  --docker-log-max-files N     Number of rotated Docker json-files to retain.
  --docker-socket-proxy-image  Pinned read-only Docker API proxy image.
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
    --collector-config-version)
      COLLECTOR_CONFIG_VERSION="$2"
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
    --ignored-paths)
      IGNORED_PATHS="$2"
      shift 2
      ;;
    --bundle-version)
      BUNDLE_VERSION="$2"
      shift 2
      ;;
    --enable-docker-logs)
      ENABLE_DOCKER_LOGS="$2"
      shift 2
      ;;
    --docker-log-max-size)
      DOCKER_LOG_MAX_SIZE="$2"
      shift 2
      ;;
    --docker-log-max-files)
      DOCKER_LOG_MAX_FILES="$2"
      shift 2
      ;;
    --docker-socket-proxy-image)
      DOCKER_SOCKET_PROXY_IMAGE="$2"
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

if ! [[ "${IGNORED_PATHS}" =~ ^/[a-zA-Z0-9_./-]+(,/[a-zA-Z0-9_./-]+)*$ ]]; then
  echo "Invalid --ignored-paths '${IGNORED_PATHS}'. Expected comma-separated absolute paths." >&2
  exit 1
fi

if ! [[ "${BUNDLE_VERSION}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Invalid --bundle-version '${BUNDLE_VERSION}'." >&2
  exit 1
fi

if ! [[ "${COLLECTOR_CONFIG_VERSION}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Invalid --collector-config-version '${COLLECTOR_CONFIG_VERSION}'." >&2
  exit 1
fi

if [[ "${ENABLE_DOCKER_LOGS}" != "true" && "${ENABLE_DOCKER_LOGS}" != "false" ]]; then
  echo "Invalid --enable-docker-logs '${ENABLE_DOCKER_LOGS}'. Expected true or false." >&2
  exit 1
fi

if ! [[ "${DOCKER_LOG_MAX_SIZE}" =~ ^[1-9][0-9]*[kKmMgG]$ ]]; then
  echo "Invalid --docker-log-max-size '${DOCKER_LOG_MAX_SIZE}'." >&2
  exit 1
fi

if ! [[ "${DOCKER_LOG_MAX_FILES}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid --docker-log-max-files '${DOCKER_LOG_MAX_FILES}'." >&2
  exit 1
fi

if ! [[ "${COLLECTOR_IMAGE}" =~ ^[a-zA-Z0-9._/@:-]+$ ]]; then
  echo "Invalid --collector-image '${COLLECTOR_IMAGE}'." >&2
  exit 1
fi

if ! [[ "${DOCKER_SOCKET_PROXY_IMAGE}" =~ ^[a-zA-Z0-9._/@:-]+$ ]]; then
  echo "Invalid --docker-socket-proxy-image '${DOCKER_SOCKET_PROXY_IMAGE}'." >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"

DOCKER_LOG_VOLUME=""
if [[ "${ENABLE_DOCKER_LOGS}" == "true" ]]; then
  DOCKER_LOG_VOLUME="      - /var/lib/docker/containers:/var/lib/docker/containers:ro"
fi

{
  echo "services:"
  cat <<EOF
  otel-collector:
    image: ${COLLECTOR_IMAGE}
    container_name: \${COMPOSE_PROJECT_NAME}-otel-collector
    command: ["--config=/etc/otelcol-contrib/config.yml"]
    restart: unless-stopped
    environment:
      OTEL_COLLECTOR_CONFIG_VERSION: ${COLLECTOR_CONFIG_VERSION}
    ports:
      - "127.0.0.1:4317:4317"
      - "127.0.0.1:4318:4318"
      - "127.0.0.1:13133:13133"
    volumes:
      - ${COLLECTOR_CONFIG}:/etc/otelcol-contrib/config.yml:ro
      - ${NODE_AUTO_DIR%/node-auto}/collector/state:/var/lib/otelcol
${DOCKER_LOG_VOLUME}
    networks:
      - ${APP_NETWORK}
      - otel-docker-socket
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 384M
    logging:
      driver: json-file
      options:
        max-size: "${DOCKER_LOG_MAX_SIZE}"
        max-file: "${DOCKER_LOG_MAX_FILES}"
EOF
  if [[ "${ENABLE_DOCKER_LOGS}" == "true" ]]; then
    cat <<EOF
    user: "0:0"
    depends_on:
      - otel-docker-socket-proxy
  otel-docker-socket-proxy:
    image: ${DOCKER_SOCKET_PROXY_IMAGE}
    container_name: \${COMPOSE_PROJECT_NAME}-otel-docker-socket-proxy
    restart: unless-stopped
    environment:
      CONTAINERS: "1"
      EVENTS: "1"
      INFO: "1"
      PING: "1"
      VERSION: "1"
      POST: "0"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - otel-docker-socket
    logging:
      driver: json-file
      options:
        max-size: "${DOCKER_LOG_MAX_SIZE}"
        max-file: "${DOCKER_LOG_MAX_FILES}"
EOF
  fi
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
    labels:
      io.opentelemetry.logs.enabled: "${ENABLE_DOCKER_LOGS}"
      io.opentelemetry.service.name: ${otel_service}
      io.opentelemetry.service.namespace: ${NAMESPACE}
      io.opentelemetry.deployment.environment: ${ENVIRONMENT}
    environment:
      NODE_OPTIONS: --require /otel-node/otel-bootstrap.js
      OTEL_BUNDLE_VERSION: ${BUNDLE_VERSION}
      OTEL_SERVICE_NAME: ${otel_service}
      OTEL_SERVICE_NAMESPACE: ${NAMESPACE}
      OTEL_DEPLOYMENT_ENVIRONMENT: ${ENVIRONMENT}
      OTEL_EXPORTER_OTLP_ENDPOINT: ${COLLECTOR_ENDPOINT}
      OTEL_EXPORTER_OTLP_PROTOCOL: grpc
      OTEL_NODE_IGNORED_PATHS: ${IGNORED_PATHS}
      OTEL_TRACES_SAMPLER: parentbased_traceidratio
      OTEL_TRACES_SAMPLER_ARG: "${SAMPLE_RATIO}"
      OTEL_RESOURCE_ATTRIBUTES: deployment.environment.name=${ENVIRONMENT},deployment.environment=${ENVIRONMENT},service.namespace=${NAMESPACE},service.type=api,host.type=ec2,cloud.provider=aws
    volumes:
      - ${NODE_AUTO_DIR}:/otel-node:ro
    logging:
      driver: json-file
      options:
        max-size: "${DOCKER_LOG_MAX_SIZE}"
        max-file: "${DOCKER_LOG_MAX_FILES}"
EOF
  done
  cat <<'EOF'
networks:
  otel-docker-socket:
    internal: true
EOF
} > "${OUTPUT}"

echo "Wrote ${OUTPUT}"

#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-install}"
CONFIG_FILE="${2:-}"

if [[ -n "${CONFIG_FILE}" ]]; then
  [[ -f "${CONFIG_FILE}" ]] || {
    echo "ERROR: Configuration file not found: ${CONFIG_FILE}" >&2
    exit 1
  }
  set -a
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  set +a
fi

APP_DIR="${APP_DIR:-}"
APP_COMPOSE_FILE="${APP_COMPOSE_FILE:-docker-compose.yml}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/signoz-ec2-observability}"
SIGNOZ_OTLP_ENDPOINT="${SIGNOZ_OTLP_ENDPOINT:-}"
DEPLOYMENT_ENVIRONMENT="${DEPLOYMENT_ENVIRONMENT:-development}"
SERVICE_NAMESPACE="${SERVICE_NAMESPACE:-application}"
OTEL_SERVICES="${OTEL_SERVICES:-}"
TRACE_SAMPLE_RATIO="${TRACE_SAMPLE_RATIO:-0.10}"
COLLECTOR_IMAGE="${COLLECTOR_IMAGE:-otel/opentelemetry-collector-contrib:0.128.0}"
APP_NETWORK="${APP_NETWORK:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERRIDE_FILE="${INSTALL_ROOT}/docker-compose.otel.yml"
COLLECTOR_CONFIG="${INSTALL_ROOT}/collector/config.yml"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "Run with sudo: sudo $0 ${ACTION}"
}

compose() {
  docker compose \
    --project-directory "${APP_DIR}" \
    -f "${APP_DIR}/${APP_COMPOSE_FILE}" \
    -f "${OVERRIDE_FILE}" \
    "$@"
}

[[ -n "${APP_DIR}" ]] || die "APP_DIR is required"
[[ -n "${APP_NETWORK}" ]] || die "APP_NETWORK is required"
[[ -n "${OTEL_SERVICES}" ]] || die "OTEL_SERVICES is required"
[[ -n "${SIGNOZ_OTLP_ENDPOINT}" ]] || die "SIGNOZ_OTLP_ENDPOINT is required"

service_args=()
IFS=',' read -r -a configured_services <<< "${OTEL_SERVICES}"
for service in "${configured_services[@]}"; do
  [[ "${service}" == *=* ]] || die "Invalid OTEL_SERVICES entry '${service}'"
  service_args+=(--service "${service}")
done

compose_services=()
for service in "${configured_services[@]}"; do
  compose_services+=("${service%%=*}")
done

preflight() {
  command -v docker >/dev/null 2>&1 || die "docker is required"
  docker compose version >/dev/null 2>&1 || die "docker compose is required"
  [[ -f "${APP_DIR}/${APP_COMPOSE_FILE}" ]] || die "Missing ${APP_DIR}/${APP_COMPOSE_FILE}"
  [[ "${SIGNOZ_OTLP_ENDPOINT}" =~ ^[a-zA-Z0-9._-]+:[0-9]+$ ]] || \
    die "SIGNOZ_OTLP_ENDPOINT must use host:port format"

  if command -v tailscale >/dev/null 2>&1; then
    tailscale status >/dev/null 2>&1 || die "Tailscale is not connected"
  fi

  for service in "${compose_services[@]}"; do
    container="$(docker compose \
      --project-directory "${APP_DIR}" \
      -f "${APP_DIR}/${APP_COMPOSE_FILE}" \
      ps -q "${service}" 2>/dev/null || true)"
    if [[ -n "${container}" ]]; then
      docker exec "${container}" node --version >/dev/null 2>&1 || \
        die "${service} is not a compatible running Node.js service"
      current_node_options="$(docker inspect -f \
        '{{range .Config.Env}}{{println .}}{{end}}' "${container}" | \
        sed -n 's/^NODE_OPTIONS=//p')"
      if [[ -n "${current_node_options}" && \
            "${current_node_options}" != *"/otel-node/otel-bootstrap.js"* ]]; then
        die "${service} already uses NODE_OPTIONS; merge it before onboarding"
      fi
    fi
  done
}

list_services() {
  command -v docker >/dev/null 2>&1 || die "docker is required"
  docker compose version >/dev/null 2>&1 || die "docker compose is required"
  [[ -f "${APP_DIR}/${APP_COMPOSE_FILE}" ]] || die "Missing ${APP_DIR}/${APP_COMPOSE_FILE}"
  docker compose \
    --project-directory "${APP_DIR}" \
    -f "${APP_DIR}/${APP_COMPOSE_FILE}" \
    config --services
}

install() {
  require_root
  preflight

  mkdir -p "${INSTALL_ROOT}/collector"
  sed "s|__SIGNOZ_OTLP_ENDPOINT__|${SIGNOZ_OTLP_ENDPOINT}|g" \
    "${TOOLKIT_DIR}/templates/collector-config.yml" > "${COLLECTOR_CONFIG}"

  INSTALL_ROOT="${INSTALL_ROOT}" "${SCRIPT_DIR}/install-node-auto.sh"

  "${SCRIPT_DIR}/render-compose-override.sh" \
    --output "${OVERRIDE_FILE}" \
    --node-auto-dir "${INSTALL_ROOT}/node-auto" \
    --collector-endpoint http://otel-collector:4317 \
    --collector-config "${COLLECTOR_CONFIG}" \
    --collector-image "${COLLECTOR_IMAGE}" \
    --app-network "${APP_NETWORK}" \
    --environment "${DEPLOYMENT_ENVIRONMENT}" \
    --namespace "${SERVICE_NAMESPACE}" \
    --sample-ratio "${TRACE_SAMPLE_RATIO}" \
    "${service_args[@]}"

  compose config --quiet
  compose up -d --no-build otel-collector "${compose_services[@]}"
  verify
}

verify() {
  preflight
  [[ -f "${OVERRIDE_FILE}" ]] || die "Run install first; ${OVERRIDE_FILE} is missing"

  compose ps otel-collector "${compose_services[@]}"
  for service in "${compose_services[@]}"; do
    container="$(compose ps -q "${service}")"
    [[ -n "${container}" ]] || die "Service ${service} is not running"
    docker exec "${container}" test -f /otel-node/otel-bootstrap.js
    docker exec "${container}" test -d /otel-node/node_modules
    docker exec "${container}" node -e \
      "require.resolve('/otel-node/node_modules/@opentelemetry/sdk-node')"

    health_status="$(docker inspect -f \
      '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
      "${container}")"
    if [[ "${health_status}" != "none" ]]; then
      for _ in {1..30}; do
        health_status="$(docker inspect -f '{{.State.Health.Status}}' "${container}")"
        [[ "${health_status}" == "healthy" ]] && break
        [[ "${health_status}" == "unhealthy" ]] && \
          die "Service ${service} became unhealthy"
        sleep 2
      done
      [[ "${health_status}" == "healthy" ]] || \
        die "Service ${service} did not become healthy within 60 seconds"
    fi
  done

  collector="$(compose ps -q otel-collector)"
  [[ -n "${collector}" ]] || die "Collector is not running"
  [[ "$(docker inspect -f '{{.State.Running}}' "${collector}")" == "true" ]] || \
    die "Collector container is not running"

  if command -v curl >/dev/null 2>&1; then
    healthy=0
    for _ in {1..15}; do
      if curl --silent --fail --max-time 2 http://127.0.0.1:13133/ >/dev/null; then
        healthy=1
        break
      fi
      sleep 2
    done
    [[ ${healthy} -eq 1 ]] || die "Collector health endpoint did not become ready"
  fi

  echo "Observability verification passed. Check SigNoz for:"
  for service in "${configured_services[@]}"; do
    echo "  service.name=${service#*=}"
  done
}

rollback() {
  require_root
  preflight
  base_services=("${compose_services[@]}")
  docker compose \
    --project-directory "${APP_DIR}" \
    -f "${APP_DIR}/${APP_COMPOSE_FILE}" \
    up -d --no-build "${base_services[@]}"
  echo "Application services recreated without the observability override."
}

case "${ACTION}" in
  list-services)
    list_services
    ;;
  preflight)
    preflight
    echo "Observability preflight passed. No changes were made."
    ;;
  install|apply)
    install
    ;;
  verify)
    verify
    ;;
  rollback)
    rollback
    ;;
  *)
    die "Usage: $0 [list-services|preflight|install|verify|rollback] [server.env]"
    ;;
esac

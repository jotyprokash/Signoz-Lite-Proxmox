#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-install}"
CONFIG_FILE="${2:-}"
DEFAULT_COLLECTOR_IMAGE="otel/opentelemetry-collector-contrib:0.153.0"
DEFAULT_DOCKER_SOCKET_PROXY_IMAGE="ghcr.io/tecnativa/docker-socket-proxy:v0.4.2"
DEFAULT_DOCKER_LOG_MAX_SIZE="20m"
DEFAULT_DOCKER_LOG_MAX_FILES="3"

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
OTEL_IGNORED_PATHS="${OTEL_IGNORED_PATHS:-/health,/ready,/live,/metrics}"
COLLECTOR_IMAGE="${COLLECTOR_IMAGE:-${DEFAULT_COLLECTOR_IMAGE}}"
APP_NETWORK="${APP_NETWORK:-}"
ENABLE_DOCKER_LOGS="${ENABLE_DOCKER_LOGS:-false}"
DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE:-${DEFAULT_DOCKER_LOG_MAX_SIZE}}"
DOCKER_LOG_MAX_FILES="${DOCKER_LOG_MAX_FILES:-${DEFAULT_DOCKER_LOG_MAX_FILES}}"
DOCKER_SOCKET_PROXY_IMAGE="${DOCKER_SOCKET_PROXY_IMAGE:-${DEFAULT_DOCKER_SOCKET_PROXY_IMAGE}}"

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
  [[ "${ENABLE_DOCKER_LOGS}" == "true" || "${ENABLE_DOCKER_LOGS}" == "false" ]] || \
    die "ENABLE_DOCKER_LOGS must be true or false"
  [[ "${DOCKER_LOG_MAX_SIZE}" =~ ^[1-9][0-9]*[kKmMgG]$ ]] || \
    die "DOCKER_LOG_MAX_SIZE must look like 20m"
  [[ "${DOCKER_LOG_MAX_FILES}" =~ ^[1-9][0-9]*$ ]] || \
    die "DOCKER_LOG_MAX_FILES must be a positive integer"
  [[ "${COLLECTOR_IMAGE}" =~ ^[a-zA-Z0-9._/@:-]+$ ]] || \
    die "COLLECTOR_IMAGE contains unsupported characters"
  [[ "${DOCKER_SOCKET_PROXY_IMAGE}" =~ ^[a-zA-Z0-9._/@:-]+$ ]] || \
    die "DOCKER_SOCKET_PROXY_IMAGE contains unsupported characters"
  if [[ "${ENABLE_DOCKER_LOGS}" == "true" ]]; then
    collector_tag="${COLLECTOR_IMAGE##*:}"
    if [[ "${collector_tag}" =~ ^0\.([0-9]+)\.[0-9]+$ ]] && \
       (( BASH_REMATCH[1] < 152 )); then
      die "Docker logs require OpenTelemetry Collector 0.152.0 or newer"
    fi
    [[ -S /var/run/docker.sock ]] || die "Docker socket is unavailable"
    [[ -d /var/lib/docker/containers ]] || \
      die "Docker json-file log directory is unavailable"
  fi

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

enable_logs() {
  require_root
  [[ -n "${CONFIG_FILE}" ]] || die "enable-logs requires a server.env path"

  backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S).$$"
  temp_file="$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")"
  cp -a "${CONFIG_FILE}" "${backup_file}"

  if ! awk \
    -v enable='"true"' \
    -v max_size="\"${DEFAULT_DOCKER_LOG_MAX_SIZE}\"" \
    -v max_files="\"${DEFAULT_DOCKER_LOG_MAX_FILES}\"" \
    -v proxy_image="\"${DEFAULT_DOCKER_SOCKET_PROXY_IMAGE}\"" \
    -v collector_image="\"${DEFAULT_COLLECTOR_IMAGE}\"" '
      BEGIN {
        values["ENABLE_DOCKER_LOGS"] = enable
        values["DOCKER_LOG_MAX_SIZE"] = max_size
        values["DOCKER_LOG_MAX_FILES"] = max_files
        values["DOCKER_SOCKET_PROXY_IMAGE"] = proxy_image
        values["COLLECTOR_IMAGE"] = collector_image
        order[1] = "ENABLE_DOCKER_LOGS"
        order[2] = "DOCKER_LOG_MAX_SIZE"
        order[3] = "DOCKER_LOG_MAX_FILES"
        order[4] = "DOCKER_SOCKET_PROXY_IMAGE"
        order[5] = "COLLECTOR_IMAGE"
      }
      {
        replaced = 0
        for (key in values) {
          if ($0 ~ "^" key "=") {
            if (!(key in seen)) {
              print key "=" values[key]
            }
            seen[key] = 1
            replaced = 1
            break
          }
        }
        if (!replaced) {
          print
        }
      }
      END {
        for (position = 1; position <= 5; position++) {
          key = order[position]
          if (!(key in seen)) {
            print key "=" values[key]
          }
        }
      }
    ' "${CONFIG_FILE}" > "${temp_file}"; then
    rm -f "${temp_file}"
    die "Unable to update ${CONFIG_FILE}"
  fi

  chown --reference="${CONFIG_FILE}" "${temp_file}"
  chmod --reference="${CONFIG_FILE}" "${temp_file}"
  mv "${temp_file}" "${CONFIG_FILE}"

  echo "Enabled Docker logs in ${CONFIG_FILE}"
  echo "Backup: ${backup_file}"
  exec "$0" preflight "${CONFIG_FILE}"
}

install() {
  require_root
  preflight

  mkdir -p "${INSTALL_ROOT}/collector/state"
  collector_template="${TOOLKIT_DIR}/templates/collector-config.yml"
  if [[ "${ENABLE_DOCKER_LOGS}" == "true" ]]; then
    collector_template="${TOOLKIT_DIR}/templates/collector-config.docker-logs.yml"
  fi
  sed "s|__SIGNOZ_OTLP_ENDPOINT__|${SIGNOZ_OTLP_ENDPOINT}|g" \
    "${collector_template}" > "${COLLECTOR_CONFIG}"
  collector_config_version="$(sha256sum "${COLLECTOR_CONFIG}" | cut -d' ' -f1)"

  INSTALL_ROOT="${INSTALL_ROOT}" "${SCRIPT_DIR}/install-node-auto.sh"

  bundle_version="$(
    sha256sum \
      "${INSTALL_ROOT}/node-auto/otel-bootstrap.js" \
      "${INSTALL_ROOT}/node-auto/package-lock.json" | \
      sha256sum | cut -d' ' -f1
  )"

  "${SCRIPT_DIR}/render-compose-override.sh" \
    --output "${OVERRIDE_FILE}" \
    --node-auto-dir "${INSTALL_ROOT}/node-auto" \
    --collector-endpoint http://otel-collector:4317 \
    --collector-config "${COLLECTOR_CONFIG}" \
    --collector-config-version "${collector_config_version}" \
    --collector-image "${COLLECTOR_IMAGE}" \
    --app-network "${APP_NETWORK}" \
    --environment "${DEPLOYMENT_ENVIRONMENT}" \
    --namespace "${SERVICE_NAMESPACE}" \
    --sample-ratio "${TRACE_SAMPLE_RATIO}" \
    --ignored-paths "${OTEL_IGNORED_PATHS}" \
    --bundle-version "${bundle_version}" \
    --enable-docker-logs "${ENABLE_DOCKER_LOGS}" \
    --docker-log-max-size "${DOCKER_LOG_MAX_SIZE}" \
    --docker-log-max-files "${DOCKER_LOG_MAX_FILES}" \
    --docker-socket-proxy-image "${DOCKER_SOCKET_PROXY_IMAGE}" \
    "${service_args[@]}"

  compose config --quiet
  observability_services=(otel-collector)
  if [[ "${ENABLE_DOCKER_LOGS}" == "true" ]]; then
    observability_services+=(otel-docker-socket-proxy)
  fi
  compose up -d --no-build "${observability_services[@]}" "${compose_services[@]}"
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

  if [[ "${ENABLE_DOCKER_LOGS}" == "true" ]]; then
    proxy="$(compose ps -q otel-docker-socket-proxy)"
    [[ -n "${proxy}" ]] || die "Docker socket proxy is not running"
    [[ "$(docker inspect -f '{{.State.Running}}' "${proxy}")" == "true" ]] || \
      die "Docker socket proxy container is not running"
    if docker logs --since 5m "${collector}" 2>&1 | \
       grep -Eq 'add_metadata_from_filepath|failed to detect a valid log path|failed to emit token'; then
      die "Docker log receiver is failing to process records"
    fi
  fi

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

  if [[ -f "${OVERRIDE_FILE}" ]]; then
    removable_services=(otel-collector)
    if compose config --services | grep -qx 'otel-docker-socket-proxy'; then
      removable_services+=(otel-docker-socket-proxy)
    fi
    compose rm -sf "${removable_services[@]}"
  fi
  echo "Application services recreated and observability containers removed."
}

case "${ACTION}" in
  enable-logs)
    enable_logs
    ;;
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
    die "Usage: $0 [enable-logs|list-services|preflight|install|verify|rollback] [server.env]"
    ;;
esac

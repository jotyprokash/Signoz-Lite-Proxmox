#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/saafir-observability}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${TOOLKIT_DIR}/node-auto"
TARGET_DIR="${INSTALL_ROOT}/node-auto"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required on the EC2 host to install the external OpenTelemetry bundle." >&2
  exit 1
fi

mkdir -p "${TARGET_DIR}"
cp "${SOURCE_DIR}/otel-bootstrap.js" "${TARGET_DIR}/otel-bootstrap.js"
cp "${SOURCE_DIR}/package.json" "${TARGET_DIR}/package.json"

cd "${TARGET_DIR}"
npm install --omit=dev

cat > "${INSTALL_ROOT}/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:-api}"
CONTAINER_PREFIX="${COMPOSE_PROJECT_NAME:-saafir-b2b-admin-panel-dev}"
CONTAINER="${CONTAINER_PREFIX}-${SERVICE}"

echo "Checking ${CONTAINER}"
docker exec "${CONTAINER}" test -f /otel-node/otel-bootstrap.js
docker exec "${CONTAINER}" test -d /otel-node/node_modules
docker exec "${CONTAINER}" printenv | grep -E 'OTEL|NODE_OPTIONS' || true
echo "Recent EC2 collector logs:"
docker logs --since 5m "${CONTAINER_PREFIX}-otel-collector" || true
EOF

chmod +x "${INSTALL_ROOT}/verify.sh"

echo "Installed OpenTelemetry Node auto-instrumentation bundle at ${TARGET_DIR}"
echo "Next: render a compose override with scripts/render-compose-override.sh"

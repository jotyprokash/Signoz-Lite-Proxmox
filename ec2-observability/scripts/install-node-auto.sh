#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/signoz-ec2-observability}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${TOOLKIT_DIR}/node-auto"
TARGET_DIR="${INSTALL_ROOT}/node-auto"

mkdir -p "${TARGET_DIR}"
cp "${SOURCE_DIR}/otel-bootstrap.js" "${TARGET_DIR}/otel-bootstrap.js"
cp "${SOURCE_DIR}/package.json" "${TARGET_DIR}/package.json"
if [[ -f "${SOURCE_DIR}/package-lock.json" ]]; then
  cp "${SOURCE_DIR}/package-lock.json" "${TARGET_DIR}/package-lock.json"
else
  rm -f "${TARGET_DIR}/package-lock.json"
fi

cd "${TARGET_DIR}"
NPM_COMMAND=(npm install --omit=dev)
if [[ -f package-lock.json ]]; then
  NPM_COMMAND=(npm ci --omit=dev)
fi

if command -v npm >/dev/null 2>&1; then
  "${NPM_COMMAND[@]}"
elif command -v docker >/dev/null 2>&1; then
  docker run --rm \
    -v "${TARGET_DIR}:/work" \
    -w /work \
    node:24-alpine \
    "${NPM_COMMAND[@]}"
else
  echo "Either npm or docker is required to install the external OpenTelemetry bundle." >&2
  exit 1
fi

docker run --rm \
  -v "${TARGET_DIR}:/otel-node:ro" \
  node:24-alpine \
  node --check /otel-node/otel-bootstrap.js

docker run --rm \
  -v "${TARGET_DIR}:/otel-node:ro" \
  node:24-alpine \
  node -e "require.resolve('/otel-node/node_modules/@opentelemetry/sdk-node')"

cat > "${INSTALL_ROOT}/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${1:?Usage: verify.sh CONTAINER_NAME [COLLECTOR_NAME]}"
COLLECTOR="${2:-}"

echo "Checking ${CONTAINER}"
docker exec "${CONTAINER}" test -f /otel-node/otel-bootstrap.js
docker exec "${CONTAINER}" test -d /otel-node/node_modules
docker exec "${CONTAINER}" printenv | grep -E 'OTEL|NODE_OPTIONS' || true
if [[ -n "${COLLECTOR}" ]]; then
  echo "Recent EC2 collector logs:"
  docker logs --since 5m "${COLLECTOR}" || true
fi
EOF

chmod +x "${INSTALL_ROOT}/verify.sh"

echo "Installed OpenTelemetry Node auto-instrumentation bundle at ${TARGET_DIR}"
echo "Next: render a compose override with scripts/render-compose-override.sh"

# EC2 Observability

## Requirements

- Docker and Docker Compose
- Application containers already running
- Private/Tailscale access to SigNoz OTLP port `4317`

## One-Time Setup

Only `/etc/signoz-ec2-observability.env` is active. The repository file is a public template used once when preparing a new server:

| File | Purpose |
| :--- | :--- |
| `ec2-observability/server.env.example` | Generic template tracked in Git; never contains real server values |
| `/etc/signoz-ec2-observability.env` | Private active configuration created separately on each EC2 host |

The application's own `.env` files are unrelated and are not modified by this toolkit.

```bash
cd /opt/Signoz-Lite-Proxmox
git pull --ff-only

sudo install -m 600 \
  ec2-observability/server.env.example \
  /etc/signoz-ec2-observability.env

sudoedit /etc/signoz-ec2-observability.env
```

Replace the example values:

```env
APP_DIR="/absolute/path/to/application"
APP_COMPOSE_FILE="docker-compose.yml"
APP_NETWORK="compose-network-name"

OTEL_SERVICES="compose-service=signoz-service-name"
SERVICE_NAMESPACE="application-namespace"
DEPLOYMENT_ENVIRONMENT="development"

SIGNOZ_OTLP_ENDPOINT="private-signoz-ip:4317"
TRACE_SAMPLE_RATIO="0.10"
OTEL_IGNORED_PATHS="/health,/ready,/live,/metrics"

ENABLE_DOCKER_LOGS="true"
DOCKER_LOG_MAX_SIZE="20m"
DOCKER_LOG_MAX_FILES="3"
DOCKER_SOCKET_PROXY_IMAGE="ghcr.io/tecnativa/docker-socket-proxy:v0.4.2"

INSTALL_ROOT="/opt/signoz-ec2-observability"
COLLECTOR_IMAGE="otel/opentelemetry-collector-contrib:0.153.0"
```

Do not add application secrets.

`ENABLE_DOCKER_LOGS="true"` collects Docker stdout/stderr only from services in
`OTEL_SERVICES`, starting at the end of each log file. The generated override
rotates enrolled service logs at `20m` and keeps three files. The collector
uses a private, read-only Docker API proxy; it does not use or publish host
port `2375`.

## Install

```bash
cd /opt/Signoz-Lite-Proxmox

sudo ./ec2-observability/scripts/onboard.sh preflight \
  /etc/signoz-ec2-observability.env

sudo ./ec2-observability/scripts/onboard.sh install \
  /etc/signoz-ec2-observability.env
```

## Update

```bash
cd /opt/Signoz-Lite-Proxmox
git pull --ff-only

sudo ./ec2-observability/scripts/onboard.sh install \
  /etc/signoz-ec2-observability.env
```

## Verify

```bash
sudo /opt/Signoz-Lite-Proxmox/ec2-observability/scripts/onboard.sh verify \
  /etc/signoz-ec2-observability.env
```

In SigNoz Logs Explorer, filter with the same service name used for traces:

```text
service.name = "signoz-service-name"
```

Docker console logs do not contain trace IDs automatically. Trace-to-log
correlation requires structured application logging that includes the active
trace and span IDs.

## Add Services

List Compose service names:

```bash
sudo /opt/Signoz-Lite-Proxmox/ec2-observability/scripts/onboard.sh list-services \
  /etc/signoz-ec2-observability.env
```

Add one Node.js service while keeping all existing mappings:

```env
OTEL_SERVICES="existing-service=existing-name,new-service=new-name"
```

```bash
sudoedit /etc/signoz-ec2-observability.env

sudo /opt/Signoz-Lite-Proxmox/ec2-observability/scripts/onboard.sh preflight \
  /etc/signoz-ec2-observability.env

sudo /opt/Signoz-Lite-Proxmox/ec2-observability/scripts/onboard.sh install \
  /etc/signoz-ec2-observability.env
```

Verify the new service in SigNoz, then repeat for the next service.

## Roll Back

```bash
sudo /opt/Signoz-Lite-Proxmox/ec2-observability/scripts/onboard.sh rollback \
  /etc/signoz-ec2-observability.env
```

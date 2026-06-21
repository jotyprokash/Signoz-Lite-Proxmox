# EC2 Observability

## Requirements

- Docker and Docker Compose
- Application containers already running
- Private/Tailscale access to SigNoz OTLP port `4317`

## One-Time Setup

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

INSTALL_ROOT="/opt/signoz-ec2-observability"
COLLECTOR_IMAGE="otel/opentelemetry-collector-contrib:0.128.0"
```

Do not add application secrets.

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

# EC2 Observability

## Requirements

- Docker and Docker Compose
- Application containers already running
- Private/Tailscale access to SigNoz OTLP port `4317`

## New Server

The repository template is public. Each server uses one private active file:
`/etc/signoz-ec2-observability.env`. Application `.env` files are untouched.

```bash
cd /opt/Signoz-Lite-Proxmox
git pull --ff-only

sudo install -m 600 \
  ec2-observability/server.env.example \
  /etc/signoz-ec2-observability.env

sudoedit /etc/signoz-ec2-observability.env
```

Edit only the server-specific values:

```env
APP_DIR="/absolute/path/to/application"
APP_COMPOSE_FILE="docker-compose.yml"
APP_NETWORK="compose-network-name"

OTEL_SERVICES="compose-service=signoz-service-name"
SERVICE_NAMESPACE="application-namespace"
DEPLOYMENT_ENVIRONMENT="development"

SIGNOZ_OTLP_ENDPOINT="private-signoz-ip:4317"
```

Do not add application secrets.

## Enable And Install

```bash
cd /opt/Signoz-Lite-Proxmox

sudo ./ec2-observability/scripts/onboard.sh enable-logs \
  /etc/signoz-ec2-observability.env

sudo ./ec2-observability/scripts/onboard.sh install \
  /etc/signoz-ec2-observability.env
```

`enable-logs` backs up the private configuration, applies pinned defaults, and
runs preflight without restarting containers. `install` applies the changes.
Only services in `OTEL_SERVICES` are collected, with `20m` x 3 local rotation.

## Update Or Verify

```bash
cd /opt/Signoz-Lite-Proxmox
git pull --ff-only

sudo ./ec2-observability/scripts/onboard.sh install \
  /etc/signoz-ec2-observability.env

sudo ./ec2-observability/scripts/onboard.sh verify \
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

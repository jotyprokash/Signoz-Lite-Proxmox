# EC2 Observability Toolkit

This toolkit connects Dockerized Node.js services on an EC2 host to a private, self-hosted SigNoz deployment without changing application source code, package files, or images.

```text
Node.js containers
  -> host-local OpenTelemetry Collector
  -> private network or Tailscale
  -> on-prem SigNoz Collector
  -> SigNoz
```

## What Is Automated

Running `onboard.sh install` performs the complete integration:

1. Validates Docker, Docker Compose, the application Compose file, selected services, Tailscale status when installed, and conflicting `NODE_OPTIONS` values.
2. Installs a locked and audited Node.js auto-instrumentation bundle under `/opt/signoz-ec2-observability` using Docker. Host npm is not required.
3. Renders an EC2 OpenTelemetry Collector configuration with memory protection, batching, retry, sending queue, and a health endpoint.
4. Renders an external Compose override that mounts instrumentation read-only into selected containers.
5. Validates the merged Compose model without printing expanded application secrets.
6. Creates or updates the host-local collector and recreates only the selected application services with `--no-build`.
7. Waits for application health checks and validates the collector health endpoint before reporting success.

Instrumentation defaults:

- OTLP/gRPC export to the host-local collector
- 10% parent-based trace sampling
- `/health`, `/ready`, `/live`, and `/metrics` excluded
- noisy Express layer spans disabled
- HTTP, NestJS, database, cache, and supported outbound dependency spans retained
- deployment environment and service namespace resource attributes

## Requirements

- Linux EC2 host with Docker and Docker Compose
- Dockerized Node.js application
- A shared application Compose network
- Private connectivity to the SigNoz OTLP/gRPC endpoint
- Tailscale connected when it provides the private route
- The application services must already have built images

## One-Time Server Configuration

The public repository contains no real hostnames, addresses, paths, or service names. Create a private configuration file once on each EC2 host:

```bash
cd /opt/Signoz-Lite-Proxmox

sudo install -m 600 \
  ec2-observability/server.env.example \
  /etc/signoz-ec2-observability.env

sudo editor /etc/signoz-ec2-observability.env
```

Set these values:

| Variable | Meaning | Example format |
| :--- | :--- | :--- |
| `APP_DIR` | Absolute application repository path | `/srv/example-application` |
| `APP_COMPOSE_FILE` | Base Compose filename | `docker-compose.yml` |
| `APP_NETWORK` | Compose network key used by the application | `application-network` |
| `OTEL_SERVICES` | Compose-to-telemetry service mappings | `web=example-web,worker=example-worker` |
| `SERVICE_NAMESPACE` | Stable product or system namespace | `example-namespace` |
| `DEPLOYMENT_ENVIRONMENT` | Deployment environment | `development` |
| `SIGNOZ_OTLP_ENDPOINT` | Private SigNoz collector address | `100.x.y.z:4317` |
| `TRACE_SAMPLE_RATIO` | Fraction of traces retained | `0.10` |

Do not place application passwords, API keys, database URLs, or cloud credentials in this file.

## Exact EC2 Commands

### First Deployment

```bash
cd /opt/Signoz-Lite-Proxmox

git fetch origin
git switch <branch-containing-the-toolkit>
git pull --ff-only

sudo ./ec2-observability/scripts/onboard.sh preflight \
  /etc/signoz-ec2-observability.env

sudo ./ec2-observability/scripts/onboard.sh install \
  /etc/signoz-ec2-observability.env
```

Expected final output:

```text
Observability verification passed. Check SigNoz for:
  service.name=<configured-service-name>
```

### Every Later Update

```bash
cd /opt/Signoz-Lite-Proxmox
git pull --ff-only

sudo ./ec2-observability/scripts/onboard.sh install \
  /etc/signoz-ec2-observability.env
```

The install command is idempotent and can safely be rerun with the same configuration.

### Verification Only

```bash
cd /opt/Signoz-Lite-Proxmox

sudo ./ec2-observability/scripts/onboard.sh verify \
  /etc/signoz-ec2-observability.env
```

### Rollback Application Instrumentation

```bash
cd /opt/Signoz-Lite-Proxmox

sudo ./ec2-observability/scripts/onboard.sh rollback \
  /etc/signoz-ec2-observability.env
```

Rollback recreates selected application services using only their base Compose file. It leaves the host collector running so other instrumented services are not interrupted.

## Adding Services

Update the private configuration file:

```env
OTEL_SERVICES="web=example-web,worker=example-worker,jobs=example-jobs"
```

Then rerun the same install command:

```bash
sudo ./ec2-observability/scripts/onboard.sh install \
  /etc/signoz-ec2-observability.env
```

Service names should be stable across container replacements. Put environment information in `DEPLOYMENT_ENVIRONMENT`, not in frequently changing service names.

## Sampling

The default ratio is:

```env
TRACE_SAMPLE_RATIO="0.10"
```

This retains approximately 10% of traces and reduces application overhead, network traffic, and SigNoz storage. Head sampling can omit errors. Use `1` only during a short validation period when every request must be visible.

## SigNoz Validation

Generate normal, non-health application traffic and search the last 15 minutes in SigNoz:

```text
service.name = '<configured-service-name>'
```

Confirm:

- new traces appear
- deployment environment matches the private configuration
- HTTP root spans contain method and response status
- collector failed-export counters remain zero

## Security

- OTLP ports bind only to EC2 loopback and the private application network.
- The on-prem endpoint should be reachable only through a private route such as Tailscale.
- Self-hosted SigNoz does not require an ingestion key for this path.
- Never share full `docker compose config` output; it expands application environment files and may reveal secrets.
- Keep `/etc/signoz-ec2-observability.env` private and out of Git.
- Prefer EC2 IAM roles over long-lived AWS access keys stored in application environment files.

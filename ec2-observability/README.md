# EC2 Observability Toolkit

This toolkit connects Dockerized Node.js services on EC2 to the on-prem SigNoz collector without changing application source, package files, or images.

```text
Node containers -> EC2 OTel gateway -> Tailscale -> on-prem SigNoz
```

## One-Command Saafir Dev Install

The defaults match the current Saafir development server. After pulling this repository on EC2:

```bash
cd /opt/Signoz-Lite-Proxmox
sudo ./ec2-observability/scripts/onboard.sh install
```

The command is idempotent. It:

- installs a pinned external Node auto-instrumentation bundle under `/opt/saafir-observability`
- generates a protected EC2 collector configuration
- generates an external Compose override
- validates the merged Compose model without printing expanded secrets
- creates or updates the EC2 collector and selected application services
- verifies the mount, packages, containers, and collector health endpoint
- excludes `/health`, `/ready`, `/live`, and `/metrics` from incoming HTTP traces
- suppresses low-value Express middleware spans while retaining request and dependency spans

The application repository remains unchanged.

## Verify And Roll Back

```bash
sudo ./ec2-observability/scripts/onboard.sh verify
sudo ./ec2-observability/scripts/onboard.sh rollback
```

Rollback recreates selected application services from their base Compose file without the observability override. It leaves the collector running so other services are not interrupted.

## Another Server

Copy `server.env.example`, edit its non-secret deployment values, and pass it to the script:

```bash
cp ec2-observability/server.env.example ec2-observability/server.env
sudo ./ec2-observability/scripts/onboard.sh install \
  ./ec2-observability/server.env
```

Do not put application secrets in this file.

## Defaults

| Setting | Default |
| :--- | :--- |
| Application directory | `/var/www/saafir/api.b2b.dev-saafir.jatritech.com` |
| Base Compose file | `docker-compose.yml` |
| Docker network | `saafir-network` |
| Services | `api=saafir-dev-api` |
| SigNoz OTLP endpoint | `100.88.205.91:4317` |
| Trace sample ratio | `0.10` |
| Collector memory limit | `384M` |

Set `TRACE_SAMPLE_RATIO=1` temporarily when validating every pilot request. A lower value reduces telemetry overhead but can omit errors because this first version uses SDK head sampling.

## Safety

- OTLP ports bind only to EC2 loopback and the private application network.
- The collector forwards through Tailscale without an ingestion key.
- The script refuses to overwrite an unrelated existing `NODE_OPTIONS` value.
- Never share full `docker compose config` output; it expands values from application environment files.
- Rotate application credentials that were previously exposed in terminal or chat output.

# EC2 Observability Toolkit

This toolkit onboards API containers to the on-prem SigNoz collector without changing the application source code or application package files.

It is designed for this flow:

```text
Node API container
-> local EC2 OpenTelemetry Collector
-> Tailscale
-> Proxmox SigNoz Collector
-> SigNoz
```

The EC2 collector must already be running and forwarding to the Proxmox collector. In the current Saafir EC2 setup, the local collector is reachable from app containers as:

```text
otel-collector:4317
```

## What This Does

- Installs OpenTelemetry Node packages outside the app repo under `/opt/saafir-observability/node-auto`.
- Mounts that external bundle into selected API containers as `/otel-node`.
- Uses `NODE_OPTIONS=--require /otel-node/otel-bootstrap.js` to auto-load tracing at process startup.
- Sends traces to the existing EC2 collector.

## What This Does Not Do

- It does not edit application source code.
- It does not edit the application `package.json`.
- It does not rebuild application images.
- It does not collect host CPU/RAM/disk metrics.
- It does not collect system logs.

## Install On EC2

Clone or pull this repo on the EC2 instance, then run:

```bash
cd /opt/Signoz-Lite-Proxmox/ec2-observability
sudo ./scripts/install-node-auto.sh
```

If the repo is cloned somewhere else, run the script from that location.

## Generate An Override

For the Saafir dev API:

```bash
sudo ./scripts/render-compose-override.sh \
  --output /opt/saafir-observability/docker-compose.otel.yml \
  --collector-endpoint http://otel-collector:4317 \
  --environment development \
  --namespace saafir \
  --service api=saafir-dev-api
```

Add more services when ready:

```bash
sudo ./scripts/render-compose-override.sh \
  --output /opt/saafir-observability/docker-compose.otel.yml \
  --collector-endpoint http://otel-collector:4317 \
  --environment development \
  --namespace saafir \
  --service api=saafir-dev-api \
  --service auth=saafir-dev-auth \
  --service chauffeur-api=saafir-dev-chauffeur-api \
  --service agency-tp-api=saafir-dev-agency-tp-api \
  --service stay=saafir-dev-stay
```

## Apply To One Service

From the app repo on EC2:

```bash
cd /var/www/saafir/api.b2b.dev-saafir.jatritech.com

docker compose \
  -f docker-compose.yml \
  -f docker-compose.local.yml \
  -f /opt/saafir-observability/docker-compose.otel.yml \
  up -d api
```

## Verify

```bash
/opt/saafir-observability/verify.sh api
```

Or manually:

```bash
docker exec saafir-b2b-admin-panel-dev-api printenv | grep -E 'OTEL|NODE_OPTIONS'
docker logs --since 5m saafir-b2b-admin-panel-dev-otel-collector
curl -i http://localhost:4000/health
```

Then check SigNoz for:

```text
service.name = saafir-dev-api
```

## Rollback

Recreate the service without the observability override:

```bash
cd /var/www/saafir/api.b2b.dev-saafir.jatritech.com

docker compose \
  -f docker-compose.yml \
  -f docker-compose.local.yml \
  up -d api
```


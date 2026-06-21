# SigNoz Dashboards

`ec2-api-overview.json` is the reusable source for the EC2 API dashboard. It
contains no server names, IP addresses, tokens, or environment-specific service
names.

## Import JSON

In SigNoz, open **Dashboards**, select **New Dashboard**, choose **Import JSON**,
and upload `ec2-api-overview.json`.

## Manage With Terraform

Requirements:

- Terraform 1.5 or newer
- SigNoz 0.85 or newer
- A SigNoz service-account API key
- An API endpoint reachable from the Terraform runner

```bash
cd dashboards/terraform

export TF_VAR_signoz_endpoint="https://signoz.example.com"
read -rsp "SigNoz API key: " TF_VAR_signoz_access_token
export TF_VAR_signoz_access_token
echo

terraform init
terraform plan -out=dashboard.tfplan
terraform apply dashboard.tfplan
```

If the dashboard was first created manually, import it before applying. Find
the dashboard ID in its URL or exported JSON:

```bash
terraform import \
  signoz_dashboard.ec2_api_overview \
  '<existing-dashboard-id>'

terraform plan -out=dashboard.tfplan
terraform apply dashboard.tfplan
```

Do not commit API keys, `.tfvars`, plans, or Terraform state. When Caddy basic
authentication protects the public endpoint, run Terraform from a trusted path
that can reach the SigNoz API and authenticate with the service-account key.

The dashboard uses official SigNoz APM/HTTP query patterns and provides:

- Log volume, severity, and warning/error count
- Latency, request rate, error percentage, and top operations
- Top HTTP endpoints, P90 endpoint latency, and slowest calls
- Database request rate, database latency, and external call statistics

The APM and HTTP panels are adapted from the Apache-2.0-licensed
[SigNoz dashboard templates](https://github.com/SigNoz/dashboards).

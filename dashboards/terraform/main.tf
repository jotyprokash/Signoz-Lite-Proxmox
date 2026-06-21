provider "signoz" {
  endpoint     = var.signoz_endpoint
  access_token = var.signoz_access_token
}

locals {
  ec2_api_overview = jsondecode(file("${path.module}/../ec2-api-overview.json"))
}

resource "signoz_dashboard" "ec2_api_overview" {
  collapsable_rows_migrated = true
  description               = local.ec2_api_overview.description
  layout                    = jsonencode(local.ec2_api_overview.layout)
  name                      = "ec2-api-overview"
  panel_map                 = jsonencode(local.ec2_api_overview.panelMap)
  tags                      = local.ec2_api_overview.tags
  title                     = local.ec2_api_overview.title
  uploaded_grafana          = local.ec2_api_overview.uploadedGrafana
  variables                 = jsonencode(local.ec2_api_overview.variables)
  version                   = local.ec2_api_overview.version
  widgets                   = jsonencode(local.ec2_api_overview.widgets)
}

output "ec2_api_overview_dashboard_id" {
  description = "SigNoz dashboard ID."
  value       = signoz_dashboard.ec2_api_overview.id
}

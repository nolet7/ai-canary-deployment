#!/usr/bin/env bash
set -euo pipefail

ACR_NAME="${ACR_NAME:-acrsrecopilotprod001}"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"

az acr login --name "$ACR_NAME"

declare -A images=(
  ["apps/api-gateway"]="sre-copilot/api-gateway"
  ["agents/orchestrator"]="sre-copilot/orchestrator"
  ["mcp-gateway"]="sre-copilot/mcp-gateway"
  ["apps/copilot-ui"]="sre-copilot/copilot-ui"
  ["apps/checkout-service"]="sre-copilot/checkout-service"
  ["mcp-servers/sentry-mcp"]="sre-copilot/sentry-mcp"
  ["mcp-servers/github-mcp"]="sre-copilot/github-mcp"
  ["mcp-servers/kubernetes-mcp"]="sre-copilot/kubernetes-mcp"
  ["mcp-servers/argocd-mcp"]="sre-copilot/argocd-mcp"
  ["mcp-servers/servicenow-mcp"]="sre-copilot/servicenow-mcp"
  ["mcp-servers/prometheus-mcp"]="sre-copilot/prometheus-mcp"
  ["mcp-servers/grafana-mcp"]="sre-copilot/grafana-mcp"
  ["mcp-servers/loki-mcp"]="sre-copilot/loki-mcp"
  ["mcp-servers/datadog-mcp"]="sre-copilot/datadog-mcp"
  ["mcp-servers/dynatrace-mcp"]="sre-copilot/dynatrace-mcp"
)

for path in "${!images[@]}"; do
  image="${images[$path]}"
  docker build -t "$ACR_LOGIN_SERVER/$image:latest" "$path"
  docker push "$ACR_LOGIN_SERVER/$image:latest"
done

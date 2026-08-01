param(
  [string]$Namespace = "monitoring",
  [string]$Deployment = "prometheus-stack-grafana"
)

$ErrorActionPreference = "Stop"

$kubectlArgs = @()
if ($env:KUBECTL_INSECURE -eq "true") {
  $kubectlArgs += "--insecure-skip-tls-verify"
}

kubectl @kubectlArgs -n $Namespace set env "deployment/$Deployment" `
  GF_AUTH_ANONYMOUS_ENABLED=true `
  GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer `
  "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org."

kubectl @kubectlArgs -n $Namespace rollout status "deployment/$Deployment" --timeout=120s

Write-Host "Grafana anonymous Viewer access is enabled. Open http://localhost:3001/d/ai-release-visibility/ai-release-visibility"

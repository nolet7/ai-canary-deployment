param(
  [string]$ApplicationManifest = "argocd\ai-canary-deployment-application.yaml",
  [switch]$Sync
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root $ApplicationManifest

$kubectlArgs = @()
if ($env:KUBECTL_INSECURE -eq "true") {
  $kubectlArgs += "--insecure-skip-tls-verify"
}

kubectl @kubectlArgs apply -f $manifest
kubectl @kubectlArgs -n argocd get application ai-canary-deployment

if ($Sync) {
  kubectl @kubectlArgs -n argocd patch application ai-canary-deployment --type merge -p '{"operation":{"sync":{"revision":"main"}}}'
  kubectl @kubectlArgs -n argocd get application ai-canary-deployment
}


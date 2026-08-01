param(
  [string]$ApplicationManifest = "argocd\ai-canary-deployment-application.yaml",
  [switch]$Sync
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root $ApplicationManifest
$repoSecret = Join-Path $root "argocd\ai-canary-repository.yaml"

$kubectlArgs = @()
if ($env:KUBECTL_INSECURE -eq "true") {
  $kubectlArgs += "--insecure-skip-tls-verify"
}

kubectl @kubectlArgs apply -f $repoSecret
kubectl @kubectlArgs apply -f $manifest
kubectl @kubectlArgs -n argocd get application ai-canary-deployment

kubectl @kubectlArgs -n argocd set env deployment/argocd-repo-server GIT_SSL_NO_VERIFY=true
kubectl @kubectlArgs -n argocd rollout status deployment/argocd-repo-server --timeout=120s

if ($Sync) {
  $patchPath = Join-Path $env:TEMP "ai-canary-deployment-sync.json"
  @'
{"operation":{"sync":{"revision":"main"}}}
'@ | Set-Content -Path $patchPath -Encoding ascii
  kubectl @kubectlArgs -n argocd patch application ai-canary-deployment --type merge --patch-file $patchPath
  kubectl @kubectlArgs -n argocd get application ai-canary-deployment
}

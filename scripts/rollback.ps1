param(
  [Parameter(Mandatory=$true)][string]$App,
  [string]$Namespace = "ai-platform"
)

$ErrorActionPreference = "Stop"
$kubectlArgs = @()
if ($env:KUBECTL_INSECURE -eq "true") {
  $kubectlArgs += "--insecure-skip-tls-verify"
}

kubectl @kubectlArgs -n $Namespace annotate ingress "$App-canary" "nginx.ingress.kubernetes.io/canary-weight=0" --overwrite
kubectl @kubectlArgs -n $Namespace scale "deployment/$App-canary" --replicas=0
kubectl @kubectlArgs -n $Namespace annotate "deployment/$App-canary" "ai-release.openai.com/manual-rollback=$(Get-Date -Format o)" --overwrite
kubectl @kubectlArgs -n $Namespace get deploy "$App-stable" "$App-canary"


param(
  [Parameter(Mandatory=$true)][string]$App,
  [int]$LocalPort = 8080,
  [string]$Namespace = "ai-platform",
  [string]$Track = ""
)

$ErrorActionPreference = "Stop"
$kubectlArgs = @()
if ($env:KUBECTL_INSECURE -eq "true") {
  $kubectlArgs += "--insecure-skip-tls-verify"
}

$service = $App
if ($Track) {
  $service = "$App-$Track"
}

Write-Host "Forwarding http://localhost:$LocalPort to service/$service in namespace $Namespace"
kubectl @kubectlArgs -n $Namespace port-forward "svc/$service" "$LocalPort`:80"


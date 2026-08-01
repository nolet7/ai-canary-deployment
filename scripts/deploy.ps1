param(
  [string]$ImageRegistry = $env:IMAGE_REGISTRY,
  [string]$KayentaImage = $env:KAYENTA_IMAGE
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (-not $ImageRegistry) {
  $ImageRegistry = "localhost:5001"
}

if (-not $KayentaImage) {
  $KayentaImage = "sihouzhao/spinnaker:kayenta"
}

$kubectlArgs = @()
if ($env:KUBECTL_INSECURE -eq "true") {
  $kubectlArgs += "--insecure-skip-tls-verify"
}

function Apply-Template($path) {
  $content = Get-Content $path -Raw
  $content = $content.Replace('${IMAGE_REGISTRY}', $ImageRegistry)
  $content = $content.Replace('${KAYENTA_IMAGE}', $KayentaImage)
  $tmp = New-TemporaryFile
  Set-Content -Path $tmp -Value $content -Encoding ascii
  kubectl @kubectlArgs apply -f $tmp
  Remove-Item $tmp
}

kubectl @kubectlArgs apply -f (Join-Path $root "k8s\apps\namespace.yaml")
Apply-Template (Join-Path $root "k8s\apps\apps.yaml")

try {
  kubectl @kubectlArgs apply -f (Join-Path $root "k8s\apps\service-monitor.yaml")
} catch {
  Write-Warning "ServiceMonitor CRD is not available or rejected. Continuing."
}

Apply-Template (Join-Path $root "k8s\kayenta\kayenta.yaml")

try {
  kubectl @kubectlArgs apply -f (Join-Path $root "k8s\observability\prometheus-rules.yaml")
} catch {
  Write-Warning "PrometheusRule CRD is not available or rejected. Continuing."
}

kubectl @kubectlArgs -n ai-platform get deploy,svc,ingress

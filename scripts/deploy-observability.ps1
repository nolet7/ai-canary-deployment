param(
  [switch]$IncludeStreamingStack
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$kubectlArgs = @()
if ($env:KUBECTL_INSECURE -eq "true") {
  $kubectlArgs += "--insecure-skip-tls-verify"
}

kubectl @kubectlArgs apply -f (Join-Path $root "k8s\observability\anomaly-exporter.yaml")
kubectl @kubectlArgs apply -f (Join-Path $root "k8s\observability\prometheus-rules.yaml")
kubectl @kubectlArgs apply -f (Join-Path $root "k8s\observability\grafana-dashboard.yaml")

if ($IncludeStreamingStack) {
  kubectl @kubectlArgs apply -f (Join-Path $root "k8s\streaming\kafka-elk.yaml")
  kubectl @kubectlArgs -n ai-observability get deploy,ds,svc
} else {
  Write-Host "Skipped Kafka/ELK. Run with -IncludeStreamingStack when the cluster has enough CPU and memory."
}

kubectl @kubectlArgs -n ai-platform get deploy ai-anomaly-exporter

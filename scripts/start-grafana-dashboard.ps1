param(
  [int]$LocalPort = 3333,
  [string]$Namespace = "monitoring",
  [string]$Service = "prometheus-stack-grafana"
)

$ErrorActionPreference = "Stop"

$kubectlArgs = @()
if ($env:KUBECTL_INSECURE -eq "true") {
  $kubectlArgs += "--insecure-skip-tls-verify"
}

$existing = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host "Port $LocalPort is already listening. Open http://localhost:$LocalPort/d/ai-release-visibility/ai-release-visibility"
  return
}

$out = Join-Path $env:TEMP "grafana-dashboard-port-forward.out.log"
$err = Join-Path $env:TEMP "grafana-dashboard-port-forward.err.log"
$args = @($kubectlArgs + @("-n", $Namespace, "port-forward", "svc/$Service", "$LocalPort`:80"))

$process = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
  $process = Start-Process -FilePath "kubectl.exe" `
    -ArgumentList $args `
    -WindowStyle Hidden `
    -RedirectStandardOutput $out `
    -RedirectStandardError $err `
    -PassThru

  Start-Sleep -Seconds 5

  try {
    $health = Invoke-WebRequest -UseBasicParsing "http://localhost:$LocalPort/api/health" -TimeoutSec 10
    Write-Host "Grafana is ready: http://localhost:$LocalPort"
    Write-Host "Dashboard: http://localhost:$LocalPort/d/ai-release-visibility/ai-release-visibility"
    Write-Host "Health: $($health.Content)"
    Write-Host "Port-forward PID: $($process.Id)"
    return
  } catch {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    if ($attempt -eq 3) {
      Write-Host "Startup logs:"
      Get-Content $out -ErrorAction SilentlyContinue
      Get-Content $err -ErrorAction SilentlyContinue
      throw
    }
    Start-Sleep -Seconds 2
  }
}

param(
  [string]$App = "customer-facing-portal",
  [int]$LocalPort = 8080,
  [string]$Namespace = "ai-platform",
  [string]$Track = "stable"
)

$ErrorActionPreference = "Stop"

$kubectlArgs = @()
if ($env:KUBECTL_INSECURE -eq "true") {
  $kubectlArgs += "--insecure-skip-tls-verify"
}

$service = "$App-$Track"
$existing = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host "Port $LocalPort is already listening. Open http://localhost:$LocalPort"
  return
}

$out = Join-Path $env:TEMP "$App-$Track-port-forward.out.log"
$err = Join-Path $env:TEMP "$App-$Track-port-forward.err.log"
$args = @($kubectlArgs + @("-n", $Namespace, "port-forward", "svc/$service", "$LocalPort`:80"))

$process = Start-Process -FilePath "kubectl.exe" `
  -ArgumentList $args `
  -WindowStyle Hidden `
  -RedirectStandardOutput $out `
  -RedirectStandardError $err `
  -PassThru

Start-Sleep -Seconds 4

try {
  $response = Invoke-WebRequest -UseBasicParsing "http://localhost:$LocalPort" -TimeoutSec 10
  Write-Host "Webpage is ready: http://localhost:$LocalPort ($($response.StatusCode), $($response.Content.Length) bytes)"
  Write-Host "Port-forward PID: $($process.Id)"
  Write-Host "Logs: $out $err"
} catch {
  Write-Host "Port-forward PID: $($process.Id)"
  Write-Host "Startup logs:"
  Get-Content $out -ErrorAction SilentlyContinue
  Get-Content $err -ErrorAction SilentlyContinue
  throw
}

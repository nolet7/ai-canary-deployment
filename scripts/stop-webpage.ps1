param(
  [int]$LocalPort = 8080
)

$connections = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
foreach ($connection in $connections) {
  $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
  if ($process -and $process.ProcessName -like "kubectl*") {
    Stop-Process -Id $process.Id -Force
    Write-Host "Stopped kubectl port-forward PID $($process.Id) on port $LocalPort"
  }
}

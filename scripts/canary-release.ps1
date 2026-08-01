param(
  [Parameter(Mandatory=$true)][string]$App,
  [Parameter(Mandatory=$true)][string]$CanaryImage,
  [Parameter(Mandatory=$true)][string]$PublicUrl,
  [string]$Weights = "5,25,50",
  [int]$AnalysisSeconds = 30,
  [string]$Namespace = "ai-platform",
  [ValidateSet("automatic", "manual")][string]$RollbackMode = "automatic",
  [string]$ArgoCdApp = "ai-canary-deployment"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
python (Join-Path $root "release_manager\ai_release_manager.py") `
  --app $App `
  --canary-image $CanaryImage `
  --public-url $PublicUrl `
  --weights $Weights `
  --analysis-seconds $AnalysisSeconds `
  --namespace $Namespace `
  --rollback-mode $RollbackMode `
  --argocd-app $ArgoCdApp

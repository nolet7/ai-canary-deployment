param(
  [string]$AppRoot = $env:APP_ROOT,
  [string]$ImageRegistry = $env:IMAGE_REGISTRY,
  [string[]]$Apps = @("customer-facing-portal", "customer-portal", "sre-operations-dashboard"),
  [switch]$Push
)

$ErrorActionPreference = "Stop"

if (-not $AppRoot) {
  $AppRoot = "C:\Users\Lateef\OneDrive\Documents\backup\ai-architecture-platform\app"
}

if (-not $ImageRegistry) {
  $ImageRegistry = "localhost:5001"
}

function Get-ImageName($app, $tag) {
  if ($ImageRegistry) {
    return "$ImageRegistry/$app`:$tag"
  }
  return "$app`:$tag"
}

function Invoke-Checked {
  param(
    [string]$command,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$arguments
  )
  & $command @arguments | ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) {
    throw "$command failed with exit code $LASTEXITCODE"
  }
}

function Import-ImageToKindNodes($image) {
  $kind = Get-Command kind -ErrorAction SilentlyContinue
  if ($kind) {
    kind load docker-image $image --name srespace-platform
    return
  }

  $nodes = docker ps --format "{{.Names}}" | Where-Object { $_ -in @("srespace-platform-control-plane", "srespace-platform-worker") }
  if (-not $nodes) {
    Write-Warning "No kind CLI and no srespace-platform node containers found. Kubernetes may not be able to pull $image."
    return
  }

  foreach ($node in $nodes) {
    Write-Host "Importing $image into $node"
    cmd /c "docker save $image | docker exec -i $node ctr --namespace k8s.io images import -"
    if ($LASTEXITCODE -ne 0) {
      throw "failed to import $image into $node"
    }
  }
}

function New-GeneratedDockerfile($projectPath, $app) {
  $package = Get-Content (Join-Path $projectPath "package.json") -Raw | ConvertFrom-Json
  $dockerfile = Join-Path $env:TEMP "$app.Dockerfile"
  if ($package.scripts.PSObject.Properties.Name -contains "build") {
    @"
FROM nginx:1.27-alpine
COPY dist /usr/share/nginx/html
EXPOSE 80
"@ | Set-Content -Path $dockerfile -Encoding ascii
  } else {
    @"
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi
COPY . .
ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000
CMD ["node", "index.js"]
"@ | Set-Content -Path $dockerfile -Encoding ascii
  }
  return $dockerfile
}

function New-DockerContext($projectPath, $app) {
  $package = Get-Content (Join-Path $projectPath "package.json") -Raw | ConvertFrom-Json
  if (-not ($package.scripts.PSObject.Properties.Name -contains "build")) {
    return $projectPath
  }

  Push-Location $projectPath
  try {
    if (-not (Test-Path "node_modules")) {
      Invoke-Checked "npm" "install"
    }
    Invoke-Checked "npm" "run" "build"
  } finally {
    Pop-Location
  }

  $context = Join-Path $env:TEMP "$app-docker-context"
  if (Test-Path $context) {
    Remove-Item -LiteralPath $context -Recurse -Force
  }
  New-Item -ItemType Directory -Path $context | Out-Null
  Copy-Item -Path (Join-Path $projectPath "dist") -Destination (Join-Path $context "dist") -Recurse
  return $context
}

foreach ($app in $Apps) {
  $project = Join-Path (Join-Path $AppRoot $app) "project"
  if (-not (Test-Path $project)) {
    Write-Warning "Skipping $app; project directory not found at $project"
    continue
  }

  $dockerfile = New-GeneratedDockerfile $project $app
  $context = New-DockerContext $project $app
  $stable = Get-ImageName $app "stable"
  $canary = Get-ImageName $app "canary"
  Write-Host "Building $stable"
  Invoke-Checked "docker" "build" "-f" $dockerfile "-t" $stable $context
  Invoke-Checked "docker" "tag" $stable $canary

  if ($Push) {
    docker push $stable
    docker push $canary
  } else {
    Import-ImageToKindNodes $stable
    Import-ImageToKindNodes $canary
  }
}

foreach ($supportImage in @("redis:7-alpine", "sihouzhao/spinnaker:kayenta", "python:3.12-alpine")) {
  Invoke-Checked "docker" "pull" $supportImage
  Import-ImageToKindNodes $supportImage
}

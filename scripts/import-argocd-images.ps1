param(
  [string[]]$Nodes = @("srespace-platform-control-plane", "srespace-platform-worker")
)

$ErrorActionPreference = "Stop"

$images = @(
  "quay.io/argoproj/argocd:v3.4.3",
  "ghcr.io/dexidp/dex:v2.45.0",
  "public.ecr.aws/docker/library/redis:8.2.3-alpine"
)

foreach ($image in $images) {
  docker pull $image
  if ($LASTEXITCODE -ne 0) {
    throw "docker pull failed for $image"
  }

  foreach ($node in $Nodes) {
    Write-Host "Importing $image into $node"
    cmd /c "docker save $image | docker exec -i $node ctr --namespace k8s.io images import -"
    if ($LASTEXITCODE -ne 0) {
      throw "failed to import $image into $node"
    }
  }
}

Write-Host "Argo CD images imported into kind nodes."

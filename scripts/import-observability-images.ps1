param(
  [string[]]$Nodes = @("srespace-platform-control-plane", "srespace-platform-worker")
)

$ErrorActionPreference = "Stop"

$images = @(
  "python:3.12-alpine",
  "bitnami/kafka:3.7",
  "docker.elastic.co/elasticsearch/elasticsearch:8.14.3",
  "docker.elastic.co/logstash/logstash:8.14.3",
  "docker.elastic.co/kibana/kibana:8.14.3",
  "docker.elastic.co/beats/filebeat:8.14.3"
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

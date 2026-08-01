# AI Canary Deployment Release Platform

This repo deploys the `ai-architecture-platform/app` applications to Kubernetes and adds AI-assisted release management around Kayenta-style canary analysis.

It is designed for Lateef's local cluster:

- Context: `kind-srespace-platform`
- Nodes: `srespace-platform-control-plane`, `srespace-platform-worker`
- Ingress: `ingress-nginx`
- Metrics: Prometheus in the `monitoring` namespace

## What This Provides

- Stable and canary Kubernetes deployments for user-facing applications.
- NGINX Ingress canary routing with adjustable traffic weight.
- Kayenta service manifests with Redis backing store.
- Prometheus ML-style anomaly score exported as `ai_release_anomaly_score`.
- Grafana dashboard for release health, anomaly score, restarts, and unavailable replicas.
- Optional Kafka + ELK pipeline for streaming live Kubernetes logs into Elasticsearch/Kibana.
- AI release manager that evaluates health, Prometheus metrics, and optional Kayenta output.
- Automatic rollback that sets canary traffic to `0` and scales canary replicas down.
- Load test script for the exposed web application.
- Port-forward helpers so you can view the application webpage locally.

## Repository Layout

```text
k8s/
  apps/                 Kubernetes app deployments, services, ingress, ServiceMonitor
  kayenta/              Kayenta + Redis manifests
  observability/        PrometheusRule for release signals
  streaming/            Optional Kafka, Filebeat, Logstash, Elasticsearch, Kibana
kayenta/
  canary-config.json    Kayenta canary metric config template
scripts/
  build-and-load.ps1    Build app images and load/push them for Kubernetes
  deploy.ps1            Apply namespace, apps, Kayenta, observability
  canary-release.ps1    Run AI-assisted canary release and rollback/promotion gate
  rollback.ps1          Manual rollback helper
  port-forward.ps1      Open local access to a deployed web app
  start-webpage.ps1     Start persistent local access to the webpage
  deploy-observability.ps1 Apply visibility, anomaly, Grafana, and optional Kafka/ELK
  load-test.ps1         Run local HTTP load test
release_manager/
  ai_release_manager.py Canary analysis and rollback engine
```

## Prerequisites

- Docker Desktop running.
- `kubectl` configured for `kind-srespace-platform`.
- PowerShell.
- Existing kube-prometheus-stack is supported and was detected in namespace `monitoring`.
- Optional but recommended: a local registry reachable by the Kubernetes nodes, such as `localhost:5001`.
- Optional: `kind` CLI. If installed, the build script can load images directly into the cluster.
- Optional: OpenAI-compatible API credentials for AI judgment.

Your current cluster may require TLS bypass for local commands. The scripts support this with:

```powershell
$env:KUBECTL_INSECURE = "true"
```

## Configure App Source

The scripts default to:

```powershell
C:\Users\Lateef\OneDrive\Documents\backup\ai-architecture-platform\app
```

Override it when needed:

```powershell
$env:APP_ROOT = "C:\Users\Lateef\OneDrive\Documents\backup\ai-architecture-platform\app"
```

## Build Images

For this local kind cluster, the default path builds images tagged with `localhost:5001` and imports them directly into the kind node containers. This works even when the `kind` CLI is not installed:

```powershell
.\scripts\build-and-load.ps1
```

To push to a real registry instead:

```powershell
$env:IMAGE_REGISTRY = "ghcr.io/nolet7"
.\scripts\build-and-load.ps1 -Push
```

The default build targets the deployed web applications:

- `customer-facing-portal`
- `customer-portal`
- `sre-operations-dashboard`

You can pass additional app folder names with `-Apps` after their services are given long-running server entry points.
- `ai-ml-sre-copilot`
- `incident-simulator`
- `order-api-backend-service`
- `feed-ingestion-gateway`
- `payment-status-servic`
- `reconciliation-worker`
- `service-order-worker`

## Deploy Platform

```powershell
$env:KUBECTL_INSECURE = "true"
$env:IMAGE_REGISTRY = "localhost:5001"
.\scripts\deploy.ps1
```

This deploys:

- Namespace `ai-platform`
- Stable and canary deployments
- Services
- NGINX canary ingress
- Kayenta + Redis in namespace `kayenta`
- Prometheus anomaly exporter and rules
- Grafana dashboard ConfigMap

The default lab Kayenta image is `sihouzhao/spinnaker:kayenta` because several historic Spinnaker Kayenta `latest` image locations no longer publish pullable manifests. Override it when you have a preferred maintained image:

```powershell
$env:KAYENTA_IMAGE = "your-registry/kayenta:tag"
```

Kayenta runtime replicas default to `0` to avoid leaving an old community image crash-looping. The Kayenta config and Redis backing service are installed; scale `deployment/kayenta` after setting a maintained `KAYENTA_IMAGE`.

## How To Test It

Run these checks after `.\scripts\build-and-load.ps1` and `.\scripts\deploy.ps1`.

### 1. Check Kubernetes Workloads

```powershell
$env:KUBECTL_INSECURE = "true"
kubectl --insecure-skip-tls-verify -n ai-platform get deploy,pods,svc,ingress
```

Expected:

- `customer-facing-portal-stable` is `2/2`.
- `customer-facing-portal-canary` is `0/0` when no release is running.
- `customer-portal` is `1/1`.
- `sre-operations-dashboard` is `1/1`.
- `ai-anomaly-exporter` is `1/1`.
- Ingresses exist for `customer-facing-portal-stable` and `customer-facing-portal-canary`.

### 2. Open The Webpage

```powershell
.\scripts\start-webpage.ps1 -App customer-facing-portal -LocalPort 8080
```

Expected:

```text
Webpage is ready: http://localhost:8080 (200, ... bytes)
```

Open:

```text
http://localhost:8080
```

If the webpage fails, check:

```powershell
kubectl --insecure-skip-tls-verify -n ai-platform get pods
kubectl --insecure-skip-tls-verify -n ai-platform logs deploy/customer-facing-portal-stable --tail=50
```

The most common local failure is no active port-forward. Re-run `start-webpage.ps1`.

If Grafana rejects the admin password in a local demo cluster, enable read-only anonymous dashboard access:

```powershell
.\scripts\enable-grafana-viewer.ps1
```

Then open:

```text
http://localhost:3001/d/ai-release-visibility/ai-release-visibility
```

### 3. Run A Web Load Test

```powershell
.\scripts\load-test.ps1 -Url http://localhost:8080 -Requests 500 -Concurrency 25
```

Expected healthy result:

```json
{
  "requests": 500,
  "ok": 500,
  "failed": 0
}
```

Latency numbers will vary by machine. For this local cluster, p95 under a few hundred milliseconds is normal for the static web app.

### 4. Check Prometheus Anomaly Score

Forward the anomaly exporter:

```powershell
kubectl --insecure-skip-tls-verify -n ai-platform port-forward svc/ai-anomaly-exporter 9108:9108
```

In another terminal:

```powershell
(Invoke-WebRequest -UseBasicParsing http://localhost:9108/metrics).Content
```

Expected:

```text
ai_release_anomaly_score{namespace="ai-platform"} 0.0000
ai_release_signal_value{signal="unavailable_replicas"} 0.0
ai_release_signal_value{signal="pod_restarts_5m"} 0.0
```

A score near `0` means normal. A score near `1` means severe release risk. Canary rollback triggers at `>= 0.75`.

### 5. Check Grafana Dashboard

Forward Grafana:

```powershell
kubectl --insecure-skip-tls-verify -n monitoring port-forward svc/prometheus-stack-grafana 3000:80
```

Open:

```text
http://localhost:3000
```

Expected:

- Dashboard named `AI Release Visibility`.
- Anomaly score panel near `0`.
- Release signal panels showing restarts, unavailable replicas, and ingress signals.

### 6. Test A Passing Canary Release

Keep the webpage port-forward running, then run:

```powershell
$env:KUBECTL_INSECURE = "true"
.\scripts\canary-release.ps1 `
  -App customer-facing-portal `
  -CanaryImage localhost:5001/customer-facing-portal:canary `
  -PublicUrl http://localhost:8080 `
  -Weights "5" `
  -AnalysisSeconds 5
```

Expected:

- Canary scales from `0` to `1`.
- Ingress canary weight changes to `5`.
- Health probes return HTTP `200`.
- Release score is `100`.
- Stable deployment is promoted.
- Canary weight returns to `0`.
- Canary scales back to `0`.

Verify:

```powershell
kubectl --insecure-skip-tls-verify -n ai-platform get deploy customer-facing-portal-stable customer-facing-portal-canary
kubectl --insecure-skip-tls-verify -n ai-platform get ingress customer-facing-portal-canary -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight}'
```

Expected:

```text
customer-facing-portal-stable   2/2
customer-facing-portal-canary   0/0
0
```

### 7. Test Rollback Behavior

Use an unreachable URL to force release failure:

```powershell
$env:KUBECTL_INSECURE = "true"
.\scripts\canary-release.ps1 `
  -App customer-facing-portal `
  -CanaryImage localhost:5001/customer-facing-portal:canary `
  -PublicUrl http://localhost:9999 `
  -Weights "5" `
  -AnalysisSeconds 1
```

Expected:

- Script exits with a failure.
- Output says canary failed and rollback is running.
- Canary ingress weight is reset to `0`.
- Canary deployment is scaled to `0`.
- Rollback reason is written as a deployment annotation.

Verify:

```powershell
kubectl --insecure-skip-tls-verify -n ai-platform get deploy customer-facing-portal-canary
kubectl --insecure-skip-tls-verify -n ai-platform describe deploy customer-facing-portal-canary
```

Expected:

- `customer-facing-portal-canary` is `0/0`.
- Annotation `ai-release.openai.com/last-rollback-reason` exists.

### 8. Test Manual Rollback

```powershell
.\scripts\rollback.ps1 -App customer-facing-portal
```

Expected:

- Canary ingress weight is `0`.
- Canary replicas are `0`.
- Manual rollback annotation is added.

### 9. Optional Kafka + ELK Test

Only run this if the local cluster has enough CPU and memory:

```powershell
.\scripts\import-observability-images.ps1
.\scripts\deploy-observability.ps1 -IncludeStreamingStack
```

Check pods:

```powershell
kubectl --insecure-skip-tls-verify -n ai-observability get pods,svc
```

Expected:

- `kafka` is running.
- `elasticsearch` is running.
- `logstash` is running.
- `kibana` is running.
- `filebeat` DaemonSet has pods on cluster nodes.

Forward Kibana:

```powershell
kubectl --insecure-skip-tls-verify -n ai-observability port-forward svc/kibana 5601:5601
```

Open:

```text
http://localhost:5601
```

Expected:

- Kibana loads.
- Elasticsearch receives indexes named `ai-platform-logs-*` after app logs are emitted.
- Built-in Elastic ML features are visible only when your Elastic license supports ML.

### 10. Cleanup Local Port-Forwards

```powershell
.\scripts\stop-webpage.ps1 -LocalPort 8080
```

For manually started foreground port-forwards, press `Ctrl+C` in that terminal.

## View The Webpage

Start persistent local access to the customer-facing portal:

```powershell
$env:KUBECTL_INSECURE = "true"
.\scripts\start-webpage.ps1 -App customer-facing-portal -LocalPort 8080
```

Open:

```text
http://localhost:8080
```

You can also port-forward:

```powershell
.\scripts\port-forward.ps1 -App sre-operations-dashboard -LocalPort 8081
.\scripts\port-forward.ps1 -App customer-portal -LocalPort 8082
```

Stop the background webpage port-forward:

```powershell
.\scripts\stop-webpage.ps1 -LocalPort 8080
```

## Visibility Stack

Deploy the lightweight visibility layer:

```powershell
$env:KUBECTL_INSECURE = "true"
.\scripts\deploy-observability.ps1
```

This adds:

- `ai-anomaly-exporter` in namespace `ai-platform`
- Prometheus metric `ai_release_anomaly_score`
- Prometheus recording and alert rules
- Grafana dashboard `AI Release Visibility`

Forward Grafana:

```powershell
kubectl --insecure-skip-tls-verify -n monitoring port-forward svc/prometheus-stack-grafana 3000:80
```

Open:

```text
http://localhost:3000
```

Deploy Kafka + ELK for streaming live logs:

```powershell
.\scripts\import-observability-images.ps1
.\scripts\deploy-observability.ps1 -IncludeStreamingStack
```

This adds namespace `ai-observability` with:

- Kafka for streaming live logs
- Filebeat DaemonSet reading Kubernetes container logs
- Logstash pipeline from Kafka to Elasticsearch
- Elasticsearch with `xpack.ml.enabled=true`
- Kibana with ML enabled

Forward Kibana:

```powershell
kubectl --insecure-skip-tls-verify -n ai-observability port-forward svc/kibana 5601:5601
```

Open:

```text
http://localhost:5601
```

Note: Elasticsearch built-in ML requires an Elastic license level that supports ML. The manifest enables ML features; the available feature set depends on your Elastic license.

## Run A Canary Release

The release manager starts with a low canary weight, evaluates the service, then promotes or rolls back.

```powershell
$env:KUBECTL_INSECURE = "true"
$env:PROMETHEUS_URL = "http://localhost:9090"
$env:KAYENTA_URL = "http://localhost:8090"
.\scripts\canary-release.ps1 `
  -App customer-facing-portal `
  -CanaryImage localhost:5001/customer-facing-portal:canary `
  -PublicUrl http://localhost:8080 `
  -Weights "5,25,50"
```

If analysis fails, rollback is automatic:

- ingress canary weight is set to `0`
- canary deployment is scaled to `0`
- release status is annotated on the deployment

Rollback also triggers when `ai_release_anomaly_score >= 0.75`.

## Optional AI Judgment

The release manager can ask an OpenAI-compatible model to classify release risk after deterministic checks run.

```powershell
$env:OPENAI_API_KEY = "<key>"
$env:OPENAI_MODEL = "gpt-4.1-mini"
```

AI judgment is advisory by default. A deterministic hard failure still rolls back even if the model is optimistic.

## Kayenta

Kayenta is deployed as a standalone service with Redis. The included `kayenta/canary-config.json` models the core metrics Kayenta should compare:

- HTTP 5xx rate
- p95 latency
- pod restart rate

Forward Kayenta locally:

```powershell
kubectl -n kayenta port-forward svc/kayenta 8090:8090
```

Kayenta is a Spinnaker service for automated canary analysis. This repo keeps Kayenta isolated so you can later wire it into Spinnaker/Argo without changing the app release flow.

Reference docs:

- [Spinnaker canary analysis setup](https://spinnaker.io/docs/setup/other_config/canary/)
- [Kayenta canary config model](https://github.com/spinnaker/kayenta/blob/master/docs/canary-config.md)

## Load Test

After port-forwarding the webpage:

```powershell
.\scripts\load-test.ps1 -Url http://localhost:8080 -Requests 500 -Concurrency 25
```

The script prints:

- total requests
- success/failure count
- requests per second
- p50/p95/p99 latency

## Manual Rollback

```powershell
.\scripts\rollback.ps1 -App customer-facing-portal
```

## Kubernetes TLS Note

If `kubectl get nodes` fails with:

```text
x509: certificate signed by unknown authority
```

use:

```powershell
$env:KUBECTL_INSECURE = "true"
```

The scripts then add `--insecure-skip-tls-verify` to `kubectl`.

## Release Flow

1. Build and publish/load stable and canary images.
2. Deploy stable application.
3. Deploy canary application beside stable.
4. Route a small percentage of traffic to canary.
5. Generate user traffic with the load test.
6. Collect health and metrics.
7. Score with deterministic checks, Kayenta-compatible signals, and optional AI judgment.
8. Promote by increasing canary traffic, or rollback immediately on failure.

## Production Hardening Checklist

- Replace `localhost:5001` with GHCR, ACR, ECR, GCR, or Harbor.
- Add CI to build versioned immutable image tags.
- Store Kayenta configs in object storage.
- Use Prometheus Adapter or ServiceMonitor labels consistently across all app services.
- Add SLO-specific Prometheus rules per service.
- Require manual approval for high-risk apps after AI/Kayenta failure.
- Add Slack/Teams notification integration on rollback.
- Remove `KUBECTL_INSECURE` once kubeconfig certificates are fixed.

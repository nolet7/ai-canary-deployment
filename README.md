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
kayenta/
  canary-config.json    Kayenta canary metric config template
scripts/
  build-and-load.ps1    Build app images and load/push them for Kubernetes
  deploy.ps1            Apply namespace, apps, Kayenta, observability
  canary-release.ps1    Run AI-assisted canary release and rollback/promotion gate
  rollback.ps1          Manual rollback helper
  port-forward.ps1      Open local access to a deployed web app
  load-test.ps1         Run local HTTP load test
release_manager/
  ai_release_manager.py Canary analysis and rollback engine
```

## Prerequisites

- Docker Desktop running.
- `kubectl` configured for `kind-srespace-platform`.
- PowerShell.
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
- Prometheus rules

The default lab Kayenta image is `sihouzhao/spinnaker:kayenta` because several historic Spinnaker Kayenta `latest` image locations no longer publish pullable manifests. Override it when you have a preferred maintained image:

```powershell
$env:KAYENTA_IMAGE = "your-registry/kayenta:tag"
```

Kayenta runtime replicas default to `0` to avoid leaving an old community image crash-looping. The Kayenta config and Redis backing service are installed; scale `deployment/kayenta` after setting a maintained `KAYENTA_IMAGE`.

## View The Webpage

Port-forward the customer-facing portal:

```powershell
.\scripts\port-forward.ps1 -App customer-facing-portal -LocalPort 8080
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

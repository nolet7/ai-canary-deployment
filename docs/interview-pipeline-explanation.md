# Interview Explanation: AI Canary Release Pipeline

## One-Minute Summary

This project demonstrates an automated release-management platform for Kubernetes. It deploys a customer-facing application through Argo CD, releases new versions with canary traffic, watches live health signals in Prometheus and Grafana, computes an ML-style anomaly score, and triggers rollback when the release looks unsafe. Rollback can be fully automatic or manually confirmed by the operator.

The goal is to show a realistic Staff SRE pattern: GitOps for desired state, progressive delivery for risk control, observability for decision-making, and human approval for high-impact rollback decisions.

## Architecture

```text
GitHub repo
  |
  | Argo CD watches main branch
  v
Argo CD Application: ai-canary-deployment
  |
  | Syncs Kubernetes desired state
  v
Kubernetes namespace: ai-platform
  |
  | Stable + canary deployments
  v
NGINX Ingress canary routing
  |
  | Traffic weight: 0%, 5%, 25%, 50%, etc.
  v
Customer-facing app

Observability path:

Kubernetes / Ingress / Pod signals
  -> Prometheus
  -> AI anomaly exporter
  -> Grafana dashboard
  -> Release manager rollback decision
```

## Key Components

### 1. GitOps With Argo CD

Argo CD is the source-of-truth controller. It watches:

```text
https://github.com/nolet7/ai-canary-deployment.git
path: .
branch: main
```

The Argo CD app is:

```text
ai-canary-deployment
```

It syncs:

- `customer-facing-portal-stable`
- `customer-facing-portal-canary`
- services and ingress
- anomaly exporter
- Prometheus rules
- Grafana dashboard ConfigMap
- Kayenta/Redis manifests

Argo CD gives visibility into drift. For example, if a live deployment image differs from Git, Argo marks the app `OutOfSync`.

### 2. Stable And Canary Deployments

The application has two deployment tracks:

```text
customer-facing-portal-stable
customer-facing-portal-canary
```

Stable handles normal traffic. Canary starts at `0` replicas and `0%` traffic. During a release, the release manager scales canary up and changes the NGINX canary weight.

The canary ingress uses:

```text
nginx.ingress.kubernetes.io/canary: "true"
nginx.ingress.kubernetes.io/canary-weight: "5"
```

That lets us route a controlled percentage of traffic to the new version.

### 3. Automated Canary Release Manager

The main release command is:

```powershell
.\scripts\canary-release.ps1 `
  -App customer-facing-portal `
  -CanaryImage localhost:5001/customer-facing-portal:canary `
  -PublicUrl http://localhost:8080 `
  -Weights "5,25,50" `
  -RollbackMode manual
```

The release manager does this:

1. Scales the canary deployment up.
2. Sets the canary image.
3. Routes a small percentage of traffic to canary.
4. Runs health checks against the public URL.
5. Queries Prometheus/anomaly metrics.
6. Scores the release.
7. Promotes if healthy.
8. Rolls back if unsafe.

### 4. Prometheus + ML-Style Anomaly Score

The anomaly exporter publishes:

```text
ai_release_anomaly_score
```

It combines signals such as:

- unavailable replicas
- pod restarts
- ingress 5xx rate
- p95 latency

Healthy expected value:

```text
ai_release_anomaly_score = 0.0000
```

Rollback threshold:

```text
>= 0.75
```

This is intentionally simple and explainable. In a production system, this can be replaced or extended with Kayenta, Elastic ML, Prometheus forecasting, or a trained anomaly model.

### 5. Grafana Release Dashboard

Grafana dashboard:

```text
AI Release Visibility
```

Local URL:

```text
http://localhost:3333/d/ai-release-visibility/ai-release-visibility
```

The dashboard shows:

- ML anomaly score
- release signals
- unavailable replicas
- pod restarts

During an interview demo, this dashboard proves that the release decision is based on observable signals, not just a script exit code.

### 6. Manual Rollback Confirmation

The release manager supports:

```text
-RollbackMode automatic
-RollbackMode manual
```

In manual mode, a failed canary pauses and asks:

```text
Manual rollback confirmation required.
Type ROLLBACK and press Enter to confirm rollback.
```

If the operator types:

```text
ROLLBACK
```

Then the release manager:

- sets canary traffic back to `0`
- scales canary replicas to `0`
- annotates the Argo CD Application with the rollback phase
- leaves the stable app serving traffic

This models a real production control where automation detects risk, but a human can confirm the remediation.

### 7. Kayenta Integration

Kayenta config is included to model automated canary analysis. The included config compares:

- HTTP 5xx rate
- p95 latency
- pod restart rate

Kayenta runtime is scaled to `0` by default because the available community image is old and not reliable for this local kind cluster. The repo still shows how Kayenta would be wired into the canary decision loop, and the release manager is structured so Kayenta scoring can be added as another gate.

### 8. Optional Kafka + ELK Visibility

The repo also includes an optional streaming/log analytics path:

```text
Filebeat -> Kafka -> Logstash -> Elasticsearch -> Kibana
```

This is useful for explaining how live logs could be streamed and analyzed alongside metrics. Elasticsearch is configured with ML enabled, but actual built-in ML features depend on the Elastic license.

## End-To-End Pipeline Flow

```text
1. Developer builds new image
2. Image is tagged as canary
3. GitOps baseline is managed by Argo CD
4. Release manager starts canary
5. NGINX routes 5% traffic to canary
6. Prometheus collects metrics
7. Anomaly exporter computes release risk score
8. Grafana visualizes release health
9. Release manager promotes or requests rollback confirmation
10. Argo CD records desired-state health and drift
```

## Demo Script

### Check Argo CD

```powershell
kubectl --insecure-skip-tls-verify -n argocd get application ai-canary-deployment
```

Expected:

```text
Synced   Healthy
```

### Open The App

```powershell
.\scripts\start-webpage.ps1
```

Open:

```text
http://localhost:8080
```

### Open Grafana

```powershell
.\scripts\start-grafana-dashboard.ps1
```

Open:

```text
http://localhost:3333/d/ai-release-visibility/ai-release-visibility
```

### Run A Healthy Load Test

```powershell
.\scripts\load-test.ps1 -Url http://localhost:8080 -Requests 500 -Concurrency 25
```

Expected:

```text
ok = 500
failed = 0
anomaly score near 0
```

### Run A Canary With Manual Rollback

```powershell
.\scripts\canary-release.ps1 `
  -App customer-facing-portal `
  -CanaryImage localhost:5001/customer-facing-portal:canary `
  -PublicUrl http://localhost:8080 `
  -Weights "5,25,50" `
  -RollbackMode manual
```

Expected healthy release:

```text
Canary passes
Stable is promoted
Canary traffic returns to 0
```

### Force A Failure

Use a bad URL:

```powershell
.\scripts\canary-release.ps1 `
  -App customer-facing-portal `
  -CanaryImage localhost:5001/customer-facing-portal:canary `
  -PublicUrl http://localhost:9999 `
  -Weights "5" `
  -AnalysisSeconds 1 `
  -RollbackMode manual
```

Expected:

```text
Manual rollback confirmation required.
```

Type:

```text
ROLLBACK
```

Then verify:

```powershell
kubectl --insecure-skip-tls-verify -n ai-platform get deploy customer-facing-portal-canary
kubectl --insecure-skip-tls-verify -n ai-platform get ingress customer-facing-portal-canary -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight}'
```

Expected:

```text
customer-facing-portal-canary   0/0
canary-weight                   0
```

## What To Say In An Interview

I built this as a progressive delivery platform. Argo CD owns the desired state, while the canary release manager controls short-lived runtime release state like canary image, replica count, and traffic weight. Prometheus and the anomaly exporter provide release intelligence, Grafana gives operators visibility, and rollback can be automatic or manually confirmed.

The important design decision is separating baseline infrastructure from release orchestration. GitOps keeps the platform reproducible, while the release manager performs controlled experiments against the canary. If the experiment fails, we reset traffic and scale the canary down. If it succeeds, we promote the stable deployment.

This is the same pattern I would use in production, with stronger image provenance, a real registry, stricter SLOs, production Kayenta or Argo Rollouts, and notification/approval integration through Slack, Teams, or ServiceNow.

## Production Improvements

- Use immutable image tags instead of `stable` and `canary`.
- Use Argo Rollouts for first-class canary objects.
- Store release decisions as Kubernetes CRDs.
- Use Kayenta or Elastic ML as a formal scoring engine.
- Add Slack/Teams approval workflows.
- Add audit events for every release phase.
- Use signed images and admission control.
- Replace local TLS bypasses with trusted cluster CA configuration.
- Add CI checks before Argo CD sync.


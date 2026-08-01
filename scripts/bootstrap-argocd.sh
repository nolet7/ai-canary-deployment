#!/usr/bin/env bash
set -euo pipefail
kubectl apply -f gitops/argocd/projects/sre-copilot-project.yaml
kubectl apply -f gitops/argocd/root-app.yaml

#!/usr/bin/env bash
set -euo pipefail

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f gitops/argocd/projects/sre-copilot-project.yaml
kubectl apply -f gitops/argocd/applications/sre-copilot-azure-prod-helm.yaml
kubectl get applications -n argocd

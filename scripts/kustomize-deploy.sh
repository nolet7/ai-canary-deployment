#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT="${1:-prod}"
kubectl apply -k "infra/kustomize/overlays/${ENVIRONMENT}"

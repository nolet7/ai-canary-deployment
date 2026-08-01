#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT="${1:-prod}"
kubectl kustomize --enable-helm "infra/kustomize/overlays/${ENVIRONMENT}"

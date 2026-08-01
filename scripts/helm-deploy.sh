#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT="${1:-prod}"
NAMESPACE="sre-copilot-${ENVIRONMENT}"

helm upgrade --install sre-copilot ./infra/helm/sre-copilot-platform \
  -n "${NAMESPACE}" --create-namespace \
  -f "./infra/helm/sre-copilot-platform/values-${ENVIRONMENT}.yaml"

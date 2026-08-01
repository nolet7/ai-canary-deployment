#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT="${1:-prod}"
helm template sre-copilot ./infra/helm/sre-copilot-platform \
  -n "sre-copilot-${ENVIRONMENT}" \
  -f "./infra/helm/sre-copilot-platform/values-${ENVIRONMENT}.yaml"

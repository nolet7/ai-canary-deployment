#!/usr/bin/env bash
set -euo pipefail

ACR_NAME="${ACR_NAME:-acrsrecopilotprod001}"
NAMESPACE="${NAMESPACE:-sre-copilot-prod}"

helm upgrade --install sre-copilot ./infra/helm/sre-copilot-platform   -n "$NAMESPACE" --create-namespace   -f ./infra/helm/sre-copilot-platform/values-azure-prod.yaml   --set global.imageRegistry="${ACR_NAME}.azurecr.io/"

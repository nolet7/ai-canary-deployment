#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-rg-sre-copilot-prod}"
AKS_NAME="${AKS_NAME:-aks-sre-copilot-prod}"

az aks get-credentials --resource-group "$RG" --name "$AKS_NAME" --overwrite-existing
kubectl get nodes

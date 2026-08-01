#!/usr/bin/env bash
set -euo pipefail

echo "Checking Azure CLI..."
az version >/dev/null

echo "Checking Terraform..."
terraform version >/dev/null

echo "Checking kubectl..."
kubectl version --client >/dev/null

echo "Checking Helm..."
helm version >/dev/null

echo "Checking Docker..."
docker version >/dev/null

echo "Azure prerequisites check passed."

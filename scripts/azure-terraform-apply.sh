#!/usr/bin/env bash
set -euo pipefail

cd infra/terraform/azure
cp -n terraform.tfvars.example terraform.tfvars || true
terraform init
terraform plan -out tfplan
terraform apply tfplan

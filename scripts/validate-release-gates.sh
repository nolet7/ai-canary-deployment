#!/usr/bin/env bash
set -euo pipefail

test -f mcp-gateway/registry.yaml
test -f mcp-gateway/policies/rbac.yaml
grep -R "production_impacting" mcp-gateway infra/helm >/dev/null
! grep -R "shell_execute\|exec_command\|run_arbitrary" apps agents mcp-gateway mcp-servers || exit 1

echo "Release gate validation passed."

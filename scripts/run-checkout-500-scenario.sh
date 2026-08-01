#!/usr/bin/env bash
set -euo pipefail

curl -fsS -X POST http://localhost:8080/copilot/ask \
  -H 'Content-Type: application/json' \
  -H 'X-User: sre-user' \
  -d '{"message":"Investigate checkout-api 500 errors, map Sentry stack trace to GitHub, check Argo CD, and recommend action.","service":"checkout-api"}' | python -m json.tool

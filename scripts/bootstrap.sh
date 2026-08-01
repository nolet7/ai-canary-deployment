#!/usr/bin/env bash
set -euo pipefail
cp -n .env.example .env || true
echo "Environment file ready: .env"
echo "Run: docker compose up --build"

#!/bin/bash
# Terminal 2: run the FastAPI gateway in the foreground
# Ctrl+C to stop.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$ROOT/.env"; set +a

cd "$ROOT/gateway"
exec "$ROOT/.venv/bin/uvicorn" main:app \
    --host 0.0.0.0 \
    --port "${GATEWAY_PORT:-8080}" \
    --workers 1

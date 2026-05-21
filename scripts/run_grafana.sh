#!/bin/bash
# Terminal 4: run Grafana in the foreground
# Ctrl+C to stop.
# Assumes grafana binary is on PATH (installed via setup.sh).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Derive root_url from RunPod pod ID if available; fall back to localhost.
# Accept an override as first argument: ./run_grafana.sh https://my-url
if [ -n "$1" ]; then
    ROOT_URL="$1"
elif [ -n "$RUNPOD_POD_ID" ]; then
    ROOT_URL="https://${RUNPOD_POD_ID}-3000.proxy.runpod.net"
else
    ROOT_URL="http://localhost:3000"
fi

echo "Grafana root_url: $ROOT_URL"

# GF_SECURITY_CSRF_TRUSTED_ORIGINS must be set as an env var — the cfg: CLI
# flag silently drops values containing "://" due to Grafana's parser.
export GF_SECURITY_CSRF_TRUSTED_ORIGINS="$ROOT_URL"
# RunPod's proxy strips the Origin header from forwarded requests. Without an
# Origin header, Grafana 13's CSRF middleware returns "origin not available"
# and blocks all datasource queries. Setting csrf_always_check=false makes
# CSRF enforcement apply only when Origin is actually present.
export GF_SECURITY_CSRF_ALWAYS_CHECK=false

exec grafana server \
    --homepath=/usr/share/grafana \
    cfg:default.paths.data="$ROOT/data/grafana" \
    cfg:default.paths.logs="$ROOT/data/grafana-logs" \
    cfg:default.paths.plugins="$ROOT/data/grafana-plugins" \
    cfg:default.paths.provisioning="$ROOT/grafana/provisioning" \
    cfg:default.server.http_port=3000 \
    cfg:default.server.root_url="$ROOT_URL" \
    cfg:default.server.serve_from_sub_path=false \
    cfg:default.security.admin_password=admin \
    cfg:default.security.allow_embedding=true \
    cfg:default.security.cookie_samesite=disabled \
    cfg:default.auth.anonymous.enabled=true \
    cfg:default.auth.anonymous.org_role=Admin

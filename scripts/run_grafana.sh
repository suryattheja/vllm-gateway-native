#!/bin/bash
# Terminal 4: run Grafana in the foreground
# Ctrl+C to stop.
# Assumes grafana-server binary is on PATH (installed via install.sh).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# GF_PATHS_* override default system paths so Grafana uses our local dirs.
# GF_PATHS_PROVISIONING points to our datasource + dashboard YAML files.
exec grafana-server \
    --homepath=/usr/share/grafana \
    cfg:default.paths.data="$ROOT/data/grafana" \
    cfg:default.paths.logs="$ROOT/data/grafana-logs" \
    cfg:default.paths.plugins="$ROOT/data/grafana-plugins" \
    cfg:default.paths.provisioning="$ROOT/grafana/provisioning" \
    cfg:default.server.http_port=3000 \
    cfg:default.security.admin_password=admin \
    cfg:default.auth.anonymous.enabled=true \
    cfg:default.security.cookie_samesite=disabled \
    cfg:default.security.allow_embedding=true

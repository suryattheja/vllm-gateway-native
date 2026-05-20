#!/bin/bash
# Terminal 3: run Prometheus in the foreground
# Ctrl+C to stop.
# Assumes prometheus binary is on PATH (installed via install.sh).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

exec prometheus \
    --config.file="$ROOT/prometheus/prometheus.yml" \
    --storage.tsdb.path="$ROOT/data/prometheus" \
    --storage.tsdb.retention.time=7d \
    --web.listen-address=0.0.0.0:9090

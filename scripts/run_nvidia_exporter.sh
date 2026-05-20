#!/bin/bash
# Terminal 5 (optional): run the NVIDIA GPU metrics exporter
# Ctrl+C to stop.
# Assumes nvidia_gpu_exporter binary is on PATH (installed via install.sh).

exec nvidia_gpu_exporter --web.listen-address=0.0.0.0:9835

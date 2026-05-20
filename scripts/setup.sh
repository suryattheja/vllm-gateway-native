#!/usr/bin/env bash
# Covers README steps 1–12: prereq checks, venv, all installs, data dirs, verification.
# Usage: bash scripts/setup.sh [--skip-nvidia-exporter] [--skip-locust] [--purge-caches]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROM_VERSION=2.52.0
EXPORTER_VERSION=1.1.0
MIN_FREE_GB=20  # abort if less than this is free on the install partition

info() { echo "[setup] $*"; }
warn() { echo "[setup] WARN: $*" >&2; }
die()  { echo "[setup] ERROR: $*" >&2; exit 1; }

SKIP_NVIDIA_EXPORTER=false
SKIP_LOCUST=false
PURGE_CACHES=false
for arg in "$@"; do
    case "$arg" in
        --skip-nvidia-exporter) SKIP_NVIDIA_EXPORTER=true ;;
        --skip-locust)          SKIP_LOCUST=true ;;
        --purge-caches)         PURGE_CACHES=true ;;
    esac
done

# --- step 1: prerequisites ---
info "Checking prerequisites..."
python3 --version           || die "python3 not found"
nvidia-smi                  || die "nvidia-smi failed — install CUDA drivers first"
python3 -m pip --version    || die "pip not found"
python3 -m venv --help > /dev/null || die "venv module not found"

# --- disk space check ---
FREE_GB=$(df -BG "$ROOT" | awk 'NR==2 {gsub("G",""); print $4}')
info "Free disk space: ${FREE_GB}G (need at least ${MIN_FREE_GB}G)"
if [ "$FREE_GB" -lt "$MIN_FREE_GB" ]; then
    warn "Low disk space. Run with --purge-caches to free pip/HF caches first."
    info "Current cache sizes:"
    du -sh ~/.cache/pip          2>/dev/null && true
    du -sh ~/.cache/huggingface  2>/dev/null && true
    die "Not enough free space (${FREE_GB}G < ${MIN_FREE_GB}G). Free space and retry."
fi

if [ "$PURGE_CACHES" = true ]; then
    info "Purging pip cache..."
    pip cache purge 2>/dev/null || python3 -m pip cache purge || true
    info "Current HF cache size (not deleted automatically — remove manually if needed):"
    du -sh ~/.cache/huggingface 2>/dev/null && true
fi

# --- detect CUDA driver version and pick matching PyTorch wheel ---
# nvidia-smi header line looks like: "CUDA Version: 12.4"
CUDA_DRIVER=$(nvidia-smi | grep -oP "CUDA Version: \K[0-9]+\.[0-9]+" || echo "unknown")
info "CUDA driver supports: $CUDA_DRIVER"

# Map driver version → closest PyTorch cu-tag (driver is always >= runtime required)
TORCH_CUDA_TAG="cu124"   # safe default for 12.4 drivers
case "$CUDA_DRIVER" in
    12.[4-9]|12.1[0-9]) TORCH_CUDA_TAG="cu124" ;;
    12.[1-3])            TORCH_CUDA_TAG="cu121" ;;
    11.*)                TORCH_CUDA_TAG="cu118" ;;
    *)
        warn "Could not detect CUDA driver version. Defaulting to cu124."
        warn "If torch fails, re-run after setting TORCH_CUDA_TAG manually in this script."
        ;;
esac
TORCH_INDEX_URL="https://download.pytorch.org/whl/${TORCH_CUDA_TAG}"
info "Using PyTorch wheel index: $TORCH_INDEX_URL"

# --- step 3: .env ---
if [ ! -f "$ROOT/.env" ]; then
    cp "$ROOT/.env.example" "$ROOT/.env"
    info ".env created from .env.example."
    info "Edit $ROOT/.env (set HF_TOKEN and API_KEYS at minimum), then re-run this script."
    exit 0
fi

# --- step 4: venv ---
info "Creating Python virtual environment..."
python3 -m venv "$ROOT/vllmenv"
source "$ROOT/vllmenv/bin/activate"
pip install --upgrade pip

# --- step 5: gateway dependencies ---
info "Installing gateway dependencies..."
pip install -r "$ROOT/gateway/requirements.txt"

# --- step 6: PyTorch (pinned to driver's CUDA) then vLLM ---
# Substitute the detected CUDA tag into requirements-ml.txt so the right wheel is used.
# Default file pins cu124; we replace it in-memory — the file on disk stays as-is.
info "Installing PyTorch + vLLM (pinned versions, $TORCH_CUDA_TAG wheels)..."
ML_REQS="$ROOT/requirements-ml.txt"
sed "s/cu124/$TORCH_CUDA_TAG/g" "$ML_REQS" | pip install -r /dev/stdin

# --- NCCL library path fix ---
# Prevents "undefined symbol: ncclCommWindowDeregister" caused by the system NCCL
# conflicting with the NCCL bundled inside PyTorch. Prepend torch's lib dir so the
# bundled NCCL is found first at runtime.
TORCH_LIB="$ROOT/vllmenv/lib/python3.10/site-packages/torch/lib"
if [ -d "$TORCH_LIB" ]; then
    info "Setting LD_LIBRARY_PATH to prefer PyTorch's bundled NCCL..."
    # Persist into the venv's activate script so every shell that sources it inherits it
    ACTIVATE="$ROOT/vllmenv/bin/activate"
    if ! grep -q "NCCL fix" "$ACTIVATE"; then
        cat >> "$ACTIVATE" <<EOF

# NCCL fix: prefer torch's bundled NCCL over system NCCL
export LD_LIBRARY_PATH="$TORCH_LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
EOF
    fi
    export LD_LIBRARY_PATH="$TORCH_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
else
    warn "torch/lib not found at $TORCH_LIB — skipping NCCL path fix"
fi

# --- step 7: Prometheus ---
info "Installing Prometheus $PROM_VERSION..."
cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
sudo mv "prometheus-${PROM_VERSION}.linux-amd64/prometheus" /usr/local/bin/
sudo mv "prometheus-${PROM_VERSION}.linux-amd64/promtool"   /usr/local/bin/
rm -rf "prometheus-${PROM_VERSION}.linux-amd64"*
cd "$ROOT"

# --- step 8: Grafana ---
info "Installing Grafana..."
sudo apt-get install -y apt-transport-https software-properties-common wget
wget -q -O - https://apt.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update -q
sudo apt-get install -y grafana

# --- step 9: NVIDIA GPU Exporter (optional) ---
if [ "$SKIP_NVIDIA_EXPORTER" = false ]; then
    info "Installing NVIDIA GPU Exporter $EXPORTER_VERSION..."
    cd /tmp
    wget -q "https://github.com/utkuozdemir/nvidia_gpu_exporter/releases/download/v${EXPORTER_VERSION}/nvidia_gpu_exporter_${EXPORTER_VERSION}_linux_x86_64.tar.gz"
    tar xzf "nvidia_gpu_exporter_${EXPORTER_VERSION}_linux_x86_64.tar.gz"
    sudo mv nvidia_gpu_exporter /usr/local/bin/
    rm -f "nvidia_gpu_exporter_${EXPORTER_VERSION}_linux_x86_64.tar.gz"
    cd "$ROOT"
else
    info "Skipping NVIDIA GPU Exporter."
fi

# --- step 10: locust (optional) ---
if [ "$SKIP_LOCUST" = false ]; then
    info "Installing locust..."
    pip install locust
else
    info "Skipping locust."
fi

# --- step 11: data directories ---
info "Creating data directories..."
mkdir -p "$ROOT/data/prometheus" "$ROOT/data/grafana" "$ROOT/data/grafana-logs" "$ROOT/data/grafana-plugins"

# --- step 12: make scripts executable + verify ---
chmod +x "$ROOT/scripts/"*.sh

info "Running verification checks..."
which python | grep -q "vllmenv" || die "venv python not active — something went wrong"
python -c "import fastapi, uvicorn, httpx, slowapi, prometheus_client, pythonjsonlogger, pydantic; print('gateway deps ok')"
python -c "import vllm; print('vllm ok')"
python -c "import torch; print('cuda:', torch.cuda.is_available(), '|', torch.cuda.get_device_name(0))"
prometheus --version
grafana-server --version
if [ "$SKIP_NVIDIA_EXPORTER" = false ]; then nvidia_gpu_exporter --version; fi
if [ "$SKIP_LOCUST" = false ]; then locust --version; fi
ls "$ROOT/data/"

info "Setup complete. Run: bash scripts/run_vllm.sh"

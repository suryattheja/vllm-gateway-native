# gateway-vllm-native

LLM inference stack (vLLM + FastAPI gateway + Prometheus + Grafana) running
natively on a Linux machine — no Docker required.

**Services and ports**

| Service           | Port  | Purpose                          |
|-------------------|-------|----------------------------------|
| vLLM              | 8000  | LLM inference (OpenAI-compatible)|
| Gateway (FastAPI) | 8080  | Auth, rate-limiting, metrics     |
| Prometheus        | 9090  | Metrics storage                  |
| Grafana           | 3000  | Dashboards                       |
| NVIDIA Exporter   | 9835  | GPU hardware metrics (optional)  |

## 1. Prerequisites

```bash
# Verify Python 3.10+ is available
python3 --version

# Verify CUDA is visible (needed by vLLM)
nvidia-smi

# Verify pip and venv are present
python3 -m pip --version
python3 -m venv --help
```

If `nvidia-smi` fails, CUDA drivers are not installed — stop here and install them first.

---

## 2. Clone the repo

```bash
git clone <your-repo-url> gateway-vllm-native
cd gateway-vllm-native
```

---

## 3. Configure environment variables

```bash
cp .env.example .env
nano .env          # or vim, or whatever editor you prefer
```

Edit these values:

```
HF_TOKEN=hf_...         # your Hugging Face read token
API_KEYS=key-dev-123    # comma-separated keys your clients will send
VLLM_URL=http://localhost:8000   # leave as-is
RATE_LIMIT_RPM=60
GATEWAY_PORT=8080
```

Qwen/Qwen2.5-3B-Instruct is not a gated model, so `HF_TOKEN` is optional for
this model — but set it anyway to get higher HF download rate limits.

---

## 4. Create a Python virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
```

> All Python installs below assume the venv is active.
> Re-activate later with: `source .venv/bin/activate`

---

## 5. Install gateway dependencies

```bash
pip install -r gateway/requirements.txt
```

This installs: fastapi, uvicorn, httpx, slowapi, prometheus-client,
python-json-logger, pydantic.

---

## 6. Install vLLM

This takes several minutes — vLLM pulls in torch and CUDA libraries.

```bash
pip install vllm
```

After install, verify it can see the GPU:

```bash
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

---

## 7. Install Prometheus

Download the pre-built binary — no compilation needed.

```bash
# Check latest version at: https://github.com/prometheus/prometheus/releases
PROM_VERSION=2.52.0
wget https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
tar xzf prometheus-${PROM_VERSION}.linux-amd64.tar.gz
sudo mv prometheus-${PROM_VERSION}.linux-amd64/prometheus /usr/local/bin/
sudo mv prometheus-${PROM_VERSION}.linux-amd64/promtool   /usr/local/bin/
rm -rf prometheus-${PROM_VERSION}.linux-amd64*

# Verify
prometheus --version
```

---

## 8. Install Grafana

```bash
sudo apt-get install -y apt-transport-https software-properties-common wget
wget -q -O - https://apt.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana

# Verify
grafana-server --version
```

---

## 9. Install NVIDIA GPU Exporter (optional)

Skip if you don't need GPU metrics in Grafana.

```bash
EXPORTER_VERSION=1.1.0
wget https://github.com/utkuozdemir/nvidia_gpu_exporter/releases/download/v${EXPORTER_VERSION}/nvidia_gpu_exporter_${EXPORTER_VERSION}_linux_x86_64.tar.gz
tar xzf nvidia_gpu_exporter_${EXPORTER_VERSION}_linux_x86_64.tar.gz
sudo mv nvidia_gpu_exporter /usr/local/bin/
rm -f nvidia_gpu_exporter_${EXPORTER_VERSION}_linux_x86_64.tar.gz

# Verify
nvidia_gpu_exporter --version
```

---

## 10. Install locust (optional — for load testing)

```bash
pip install locust

# Verify
locust --version
```

---

## 11. Create local data directories

Prometheus and Grafana need somewhere to store their data.

```bash
mkdir -p data/prometheus data/grafana data/grafana-logs data/grafana-plugins
```

---

## 12. Verify every installation

Run these checks after completing steps 4–11. Every command should print a
version string or "ok" — no errors.

```bash
# Python venv active?
which python
# should print something ending in .venv/bin/python

# Gateway Python packages
python -c "import fastapi, uvicorn, httpx, slowapi, prometheus_client, pythonjsonlogger, pydantic; print('gateway deps ok')"

# vLLM + CUDA
python -c "import vllm; print('vllm ok')"
python -c "import torch; print('cuda:', torch.cuda.is_available(), '|', torch.cuda.get_device_name(0))"

# Prometheus binary
prometheus --version
# expected: prometheus, version 2.52.0 (or similar)

# Grafana binary
grafana-server --version
# expected: Version X.X.X (...)

# NVIDIA GPU Exporter (skip if not installed)
nvidia_gpu_exporter --version

# Locust (skip if not installed)
locust --version

# Data directories exist
ls data/
# expected: grafana  grafana-logs  grafana-plugins  prometheus

# Scripts are executable
ls -l scripts/
# expected: -rwxr-xr-x for each .sh file
```

If any command fails, re-run the corresponding install step.

---

## 12. Make scripts executable

```bash
chmod +x scripts/*.sh
```

---

## Running — one terminal per service

Open a separate terminal (or tmux pane) for each. They all log to stdout.

### Terminal 1 — vLLM

```bash
bash scripts/run_vllm.sh
```

vLLM will download the model weights on first run (~6 GB). Wait until you see:

```
INFO:     Application startup complete.
```

Then verify:

```bash
curl http://localhost:8000/health
# → {"status":"ok"}

curl http://localhost:8000/v1/models
# → lists qwen2.5-3b
```

---

### Terminal 2 — Gateway

Wait for vLLM to be healthy before starting this.

```bash
bash scripts/run_gateway.sh
```

Verify:

```bash
curl http://localhost:8080/health
# → {"status":"ok"}

# Test a real request
curl http://localhost:8080/v1/chat/completions \
  -H "X-API-Key: key-dev-123" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-3b",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'
```

---

### Terminal 3 — Prometheus

```bash
bash scripts/run_prometheus.sh
```

Open in browser: http://localhost:9090

Try a query: `gateway_requests_total`

---

### Terminal 4 — Grafana

```bash
bash scripts/run_grafana.sh
```

Open in browser: http://localhost:3000  
Login: admin / admin

The Prometheus data source is auto-provisioned — you should see it under
**Configuration → Data Sources**.

---

### Terminal 5 — NVIDIA GPU Exporter (optional)

```bash
bash scripts/run_nvidia_exporter.sh
```

---

## Adding a vLLM Grafana dashboard

1. Go to https://grafana.com/grafana/dashboards/17619
2. Download the JSON
3. In Grafana: **Dashboards → Import → Upload JSON**

Or drop the JSON file into `grafana/dashboards/` and restart Grafana — it will
be auto-loaded via the provisioning config in
`grafana/provisioning/dashboards/dashboard.yml`.

---

## Running load tests

```bash
# Make sure the venv is active and the gateway is running
source .venv/bin/activate
cd loadtest

# Headless (prints stats to terminal)
locust -f locustfile.py --headless \
  --host http://localhost:8080 \
  --users 5 --spawn-rate 1 --run-time 2m

# With browser UI at http://localhost:8089
locust -f locustfile.py --host http://localhost:8080
```

---

## Quick reference — what each script does

| Script                       | What it runs                       |
|------------------------------|------------------------------------|
| `scripts/run_vllm.sh`        | vLLM inference server on :8000     |
| `scripts/run_gateway.sh`     | FastAPI gateway on :8080           |
| `scripts/run_prometheus.sh`  | Prometheus on :9090                |
| `scripts/run_grafana.sh`     | Grafana on :3000                   |
| `scripts/run_nvidia_exporter.sh` | GPU metrics exporter on :9835  |

---

## File layout

```
gateway-vllm-native/
├── .env                        # your secrets (never commit)
├── .env.example                # template
├── gateway/
│   ├── main.py                 # FastAPI app, proxy logic
│   ├── auth.py                 # API key authentication
│   ├── middleware.py           # structured logging + Prometheus metrics
│   └── requirements.txt
├── prometheus/
│   └── prometheus.yml          # scrape targets (all localhost)
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/prometheus.yml
│   │   └── dashboards/dashboard.yml
│   └── dashboards/             # drop dashboard JSON files here
├── loadtest/
│   └── locustfile.py
├── scripts/
│   ├── run_vllm.sh
│   ├── run_gateway.sh
│   ├── run_prometheus.sh
│   ├── run_grafana.sh
│   └── run_nvidia_exporter.sh
└── data/                       # created by step 11, not committed
    ├── prometheus/
    ├── grafana/
    ├── grafana-logs/
    └── grafana-plugins/
```

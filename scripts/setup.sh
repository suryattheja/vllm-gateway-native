#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env
if [ ! -f "$ROOT/.env" ]; then
    cp "$ROOT/.env.example" "$ROOT/.env"
    echo "Created .env — fill in HF_TOKEN and API_KEYS, then re-run."
    exit 0
fi

# venv
python3 -m venv "$ROOT/vllmenv" --system-site-packages
source "$ROOT/vllmenv/bin/activate"
pip install --upgrade pip -q
echo "venv ok"

# gateway deps
pip install -r "$ROOT/gateway/requirements.txt" -q
echo "gateway deps ok"

# vllm
pip install vllm==0.4.2 -q
echo "vllm ok"

# locust
pip install locust -q
echo "locust ok"

# prometheus
PROM_VERSION=2.52.0
cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
sudo mv "prometheus-${PROM_VERSION}.linux-amd64/prometheus" /usr/local/bin/
sudo mv "prometheus-${PROM_VERSION}.linux-amd64/promtool" /usr/local/bin/
rm -rf "prometheus-${PROM_VERSION}.linux-amd64"*
echo "prometheus ok"

# grafana
sudo apt-get install -y -q apt-transport-https software-properties-common wget
wget -q -O - https://apt.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
sudo apt-get update -q
sudo apt-get install -y -q grafana
echo "grafana ok"

# nvidia gpu exporter
EXPORTER_VERSION=1.1.0
cd /tmp
wget -q "https://github.com/utkuozdemir/nvidia_gpu_exporter/releases/download/v${EXPORTER_VERSION}/nvidia_gpu_exporter_${EXPORTER_VERSION}_linux_x86_64.tar.gz"
tar xzf "nvidia_gpu_exporter_${EXPORTER_VERSION}_linux_x86_64.tar.gz"
sudo mv nvidia_gpu_exporter /usr/local/bin/
rm -f "nvidia_gpu_exporter_${EXPORTER_VERSION}_linux_x86_64.tar.gz"
echo "nvidia_gpu_exporter ok"

cd "$ROOT"

# data dirs + permissions
mkdir -p data/prometheus data/grafana data/grafana-logs data/grafana-plugins
chmod +x scripts/*.sh
echo "dirs ok"

echo ""
echo "Setup complete. Run: bash scripts/run_vllm.sh"
#!/bin/bash
# Run three sequential load tests at increasing concurrency.
# Usage: bash loadtest/run_benchmarks.sh [http://localhost:8080]
# Run from the repo root with the venv active.

GATEWAY="${1:-http://localhost:8080}"
RESULTS_DIR="./loadtest/results"
mkdir -p "$RESULTS_DIR"

echo "Target: $GATEWAY"

if ! curl -sf "$GATEWAY/health" > /dev/null; then
    echo "ERROR: gateway not reachable at $GATEWAY"
    exit 1
fi

echo "[1/3] 1 user, 2 min (baseline)"
locust -f loadtest/locustfile.py --headless \
  --host "$GATEWAY" --users 1 --spawn-rate 1 --run-time 2m \
  --csv "$RESULTS_DIR/c1" --html "$RESULTS_DIR/report_1x.html"

echo "Cooling down 15s..."
sleep 15

echo "[2/3] 5 users, 3 min"
locust -f loadtest/locustfile.py --headless \
  --host "$GATEWAY" --users 5 --spawn-rate 2 --run-time 3m \
  --csv "$RESULTS_DIR/c5" --html "$RESULTS_DIR/report_5x.html"

echo "Cooling down 15s..."
sleep 15

echo "[3/3] 10 users, 3 min"
locust -f loadtest/locustfile.py --headless \
  --host "$GATEWAY" --users 10 --spawn-rate 3 --run-time 3m \
  --csv "$RESULTS_DIR/c10" --html "$RESULTS_DIR/report_10x.html"

echo ""
echo "Done. Results in $RESULTS_DIR/"
ls -lh "$RESULTS_DIR/"

#!/bin/bash
# Terminal 1: run vLLM in the foreground
# Ctrl+C to stop.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$ROOT/.env"; set +a

export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"

exec "$ROOT/vllmenv/bin/python" -m vllm.entrypoints.openai.api_server \
    --model Qwen/Qwen2.5-3B-Instruct \
    --dtype float16 \
    --max-model-len 8192 \
    --gpu-memory-utilization 0.85 \
    --max-num-batched-tokens 8192 \
    --max-num-seqs 256 \
    --enable-prefix-caching \
    --served-model-name qwen2.5-3b \
    --tensor-parallel-size 1 \
    --host 0.0.0.0 \
    --port 8000

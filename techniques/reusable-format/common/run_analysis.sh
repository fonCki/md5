#!/usr/bin/env bash
set -euo pipefail
FMT="${1:-}"; OUT="${2:-}"
[[ -n "$FMT" && -n "$OUT" ]] || { echo "usage: run_analysis.sh <jpeg|pdf|gzip> <out_dir>"; exit 2; }
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "${ROOT}/verify_reusable.py" --format "$FMT" --out-dir "$OUT"
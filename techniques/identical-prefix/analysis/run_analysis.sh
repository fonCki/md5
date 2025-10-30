#!/usr/bin/env bash
set -euo pipefail
SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(cd "$SELF/../out" && pwd)"
python3 "$SELF/verify_identical.py" --out-dir "$OUT_DIR"

#!/usr/bin/env bash
set -euo pipefail
SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(cd "$SELF/../out" && pwd)"
COMMON="$(cd "$SELF/../../common" && pwd)"
python3 "$COMMON/verify_reusable.py" --format jpeg --out-dir "$OUT_DIR"
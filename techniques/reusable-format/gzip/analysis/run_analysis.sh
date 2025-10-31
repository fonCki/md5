#!/usr/bin/env bash
set -euo pipefail

SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(cd "$SELF/../out" && pwd)"
COMMON="$(cd "$SELF/../../common" && pwd)"

# nota: usa el verificador comun para gzip
python3 "$COMMON/verify_reusable.py" --format gzip --out-dir "$OUT_DIR"

#!/usr/bin/env bash
# Author: Alfonso Pedro Ridao (s243942)
set -euo pipefail

# nota: analiza archivos PDF con collision blocks
SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(cd "$SELF/../out" && pwd)"
COMMON="$(cd "$SELF/../../common" && pwd)"

python3 "$COMMON/verify_reusable.py" --format pdf --out-dir "$OUT_DIR"

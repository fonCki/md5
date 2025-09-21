#!/usr/bin/env bash
set -euo pipefail

OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac

done
[[ -n "$OUT" ]] || { echo "missing --out-dir"; exit 2; }
mkdir -p "$OUT"

# Centralize artifact paths
T1="$OUT/t1.bin"
T2="$OUT/t2.bin"
MANIFEST="$OUT/manifest.json"
readonly OUT T1 T2 MANIFEST

# TODO: replace this stub with your real generator
echo "stub-A" > "$T1"
echo "stub-B" > "$T2"

# Manifest
cat > "$MANIFEST" <<JSON
{
  "technique": "identical-prefix",
  "language": "free-choice",
  "artifacts": ["t1.bin","t2.bin"],
  "notes": "stub; replace with real outputs"
}
JSON

# Also print manifest to stdout
cat "$MANIFEST"

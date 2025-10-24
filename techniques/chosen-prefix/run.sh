#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# run_cpc_merged.sh
# High-level driver for an MD5 chosen-prefix collision demo (SAFE TEMPLATE).
#
# - Preserves the pipeline from your first script (prefix prep, padding, tail assembly,
#   PDF wrapping, checksum verification).
# - The actual "chosen-prefix collision generation" step is a STUB by default.
#   Replace that block with your real generator if you choose to run it.
#
# Usage:
#   ./run.sh
#
# Environment variables you can override:
#   HASHCLASH_DIR   : path to hashclash checkout (if you intend to use it)
#   WORKLEVEL       : forwarded to your generator if needed (default: 2)
#   SCRIPTS_DIR     : where pad_to_block.py and pdf_wrap.py live (default: src)
#   NTHREADS        : threads for your generator (default: nproc or 1)

#######################
# Parse args
#######################
OUT="out" # default output dir
# remove OUT if it exists to avoid confusion
if [ -d "$OUT" ]; then
  rm -rrf "$OUT" # careful with rm -rf! We just want a clean output dir.
fi
mkdir -p "$OUT"

#######################
# Config / filenames
#######################
HASHCLASH_DIR="${HASHCLASH_DIR:-$HOME/src/hashclash}"
export WORKLEVEL="${WORKLEVEL:-2}"
SCRIPTS_DIR="${SCRIPTS_DIR:-src}"

# Helper scripts
PAD_SCRIPT="${SCRIPTS_DIR}/pad_to_block.py"
PDF_WRAP="${SCRIPTS_DIR}/pdf_wrap.py"

# Centralize artifact paths (everything inside OUT)
PREFIX_A="$OUT/prefixA.bin"
PREFIX_B="$OUT/prefixB.bin"
SA="$OUT/SA.bin"               # colliding expansion A (from generator)
SB="$OUT/SB.bin"               # colliding expansion B (from generator)
COMMON_TAIL="$OUT/common_tail.bin"
TAIL_A="$OUT/tailA.bin"
TAIL_B="$OUT/tailB.bin"
OUT1="$OUT/collision1.pdf"
OUT2="$OUT/collision2.pdf"
MANIFEST="$OUT/manifest.json"
readonly OUT PREFIX_A PREFIX_B SA SB COMMON_TAIL TAIL_A TAIL_B OUT1 OUT2 MANIFEST

# threads
NTHREADS="${NTHREADS:-$(nproc 2>/dev/null || echo 1)}"

########################
# Check dependencies (only the ones this wrapper actually uses)
########################
command -v python3 >/dev/null 2>&1 || { echo "python3 required but not found. Install Python 3."; exit 1; }
command -v md5sum  >/dev/null 2>&1 || { echo "md5sum required but not found. Install coreutils."; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum required but not found. Install coreutils."; exit 1; }

# Helper scripts present?
[[ -f "$PAD_SCRIPT" ]] || { echo "ERROR: $PAD_SCRIPT not found. Provide a 64-byte padding helper."; exit 1; }
[[ -f "$PDF_WRAP"  ]] || { echo "ERROR: $PDF_WRAP not found. Provide a simple PDF wrapper helper."; exit 1; }
chmod +x "$PAD_SCRIPT" "$PDF_WRAP"

########################
# 1) Create example prefixes & tail if missing (all within OUT)
########################
if [ ! -f "${PREFIX_A}" ]; then
  printf "Invoice: Q3 / benign\n" > "${PREFIX_A}"
  echo "Wrote example ${PREFIX_A}"
fi
if [ ! -f "${PREFIX_B}" ]; then
  printf "Wire transfer: URGENT\n" > "${PREFIX_B}"
  echo "Wrote example ${PREFIX_B}"
fi
if [ ! -f "${COMMON_TAIL}" ]; then
  echo "No ${COMMON_TAIL} found; creating a 4 KiB zero tail for demo."
  truncate -s 4096 "${COMMON_TAIL}"
fi

########################
# 2) Align prefixes
########################
echo "Padding prefixes to 64-byte blocks..."
python3 "${PAD_SCRIPT}" "${PREFIX_A}" "${PREFIX_B}"

########################
# 3) Run chosen-prefix generator (WORKING)
#    Prefer direct cpc_md5; fallback to scripts/cpc.sh
########################
echo "Running chosen-prefix collision generator..."
if [[ -x "${MD5_CPC_BIN}" ]]; then
  # Direct binary path
  "${MD5_CPC_BIN}" \
    --prefixfile1 "${PREFIX_A}" --prefixfile2 "${PREFIX_B}" \
    --out1 "${SA}" --out2 "${SB}" \
    --threads "${NTHREADS}" \
    --worklevel "${WORKLEVEL}"
else
  # Fallback to repo script
  workdir="${HASHCLASH_DIR}/cpc_workdir"
  mkdir -p "${workdir}"
  cp -f "${PREFIX_A}" "${PREFIX_B}" "${workdir}/"
  (
    cd "${workdir}"
    ../scripts/cpc.sh "$(basename "${PREFIX_A}")" "$(basename "${PREFIX_B}")"
  )
  # Collect outputs (standard names or newest two files)
  if [ -f "${workdir}/collision1.bin" ] && [ -f "${workdir}/collision2.bin" ]; then
    cp -f "${workdir}/collision1.bin" "${SA}"
    cp -f "${workdir}/collision2.bin" "${SB}"
  else
    mapfile -t newest < <(ls -t "${workdir}"/* 2>/dev/null | head -n 2)
    [[ ${#newest[@]} -eq 2 ]] || { echo "ERROR: Could not locate collision outputs in ${workdir}"; exit 1; }
    cp -f "${newest[0]}" "${SA}"
    cp -f "${newest[1]}" "${SB}"
  fi
fi

[[ -s "$SA" && -s "$SB" ]] || { echo "ERROR: generator produced empty outputs."; exit 1; }

########################
# 4) Assemble collided payloads
########################
echo "Assembling tails..."
cat "${SA}" "${COMMON_TAIL}" > "${TAIL_A}"
cat "${SB}" "${COMMON_TAIL}" > "${TAIL_B}"

########################
# 5) Wrap into PDFs (two openable files)
########################
echo "Wrapping into PDFs..."
python3 "${PDF_WRAP}" "${PREFIX_A}" "${SA}" "${COMMON_TAIL}" "${PDF1}"
python3 "${PDF_WRAP}" "${PREFIX_B}" "${SB}" "${COMMON_TAIL}" "${PDF2}"

########################
# 6) Verify digests
########################
echo "MD5 sums:"
md5sum "${OUT1}" "${OUT2}" || true
echo
echo "SHA256 sums:"
sha256sum "${OUT1}" "${OUT2}" || true

########################
# 7) Emit manifest (file + stdout)
########################
cat > "${MANIFEST}" <<JSON
{
  "technique": "chosen-prefix",
  "language": "bash",
  "artifacts": [
    "$(basename "${OUT1}")",
    "$(basename "${OUT2}")",
    "$(basename "${SA}")",
    "$(basename "${SB}")",
    "$(basename "${COMMON_TAIL}")"
  ],
  "worklevel": "${WORKLEVEL}",
  "threads": "${NTHREADS}",
  "notes": "This run uses a safe STUB for the generator step. Replace the stub with your real generator if appropriate."
}
JSON

# Also print manifest to stdout
cat "${MANIFEST}"

echo
echo "Done. Outputs in: ${OUT}"

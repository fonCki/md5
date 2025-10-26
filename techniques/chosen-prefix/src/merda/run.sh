#!/usr/bin/env bash
set -euo pipefail
# Defaults that are safe with `set -u`
: "${HASHCLASH_DIR:=$HOME/src/hashclash}"
: "${WORKLEVEL:=2}"
: "${SCRIPTS_DIR:=$(dirname "$0")/src}"
: "${NTHREADS:=$(command -v nproc >/dev/null 2>&1 && nproc || echo 1)}"
: "${MD5_CPC_BIN:=${HASHCLASH_DIR}/projects/md5_chosen_prefix_collisions/cpc_md5}"

IFS=$'\n\t'


#######################
# Parse args
#######################
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -n "$OUT" ]] || { echo "missing --out-dir"; exit 2; }
mkdir -p "$OUT"

#######################
# Config
#######################
HASHCLASH_DIR="${HASHCLASH_DIR:-$HOME/src/hashclash}"
WORKLEVEL="${WORKLEVEL:-2}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(dirname "$0")/src}"

MD5_CPC_BIN="${MD5_CPC_BIN:-${HASHCLASH_DIR}/projects/md5_chosen_prefix_collisions/cpc_md5}"
NTHREADS="${NTHREADS:-$(nproc 2>/dev/null || echo 1)}"

# Helper scripts
PAD_SCRIPT="pad_to_block.py"
PDF_WRAP="pdf_wrap.py"

# Artifacts under OUT
PREFIX_A="$OUT/prefixA.bin"
PREFIX_B="$OUT/prefixB.bin"
SA="$OUT/SA.bin"
SB="$OUT/SB.bin"
COMMON_TAIL="$OUT/common_tail.bin"
TAIL_A="$OUT/tailA.bin"
TAIL_B="$OUT/tailB.bin"
PDF1="$OUT/collision1.pdf"
PDF2="$OUT/collision2.pdf"
T1="$OUT/t1.bin"
T2="$OUT/t2.bin"
MANIFEST="$OUT/manifest.json"

readonly OUT PREFIX_A PREFIX_B SA SB COMMON_TAIL TAIL_A TAIL_B PDF1 PDF2 T1 T2 MANIFEST

#######################
# Dependencies
#######################
command -v git >/dev/null 2>&1 || { echo "git required."; exit 1; }
command -v make >/dev/null 2>&1 || { echo "make required."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required."; exit 1; }
command -v md5sum >/dev/null 2>&1 || { echo "md5sum required."; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum required."; exit 1; }

[[ -f "$PAD_SCRIPT" ]] || { echo "ERROR: $PAD_SCRIPT not found."; exit 1; }
[[ -f "$PDF_WRAP"  ]] || { echo "ERROR: $PDF_WRAP not found."; exit 1; }
chmod +x "$PAD_SCRIPT" "$PDF_WRAP"

########################
# HashClash: clone/build if needed
########################
if [ ! -d "${HASHCLASH_DIR}" ]; then
  echo "Cloning HashClash into ${HASHCLASH_DIR}..."
  git clone https://github.com/cr-marcstevens/hashclash "${HASHCLASH_DIR}"
fi

if [ ! -f "${HASHCLASH_DIR}/scripts/cpc.sh" ]; then
  echo "ERROR: unexpected repo layout; scripts/cpc.sh missing in ${HASHCLASH_DIR}."
  exit 1
fi

# Build if cpc binary isn’t present and md5fastcoll isn’t built yet
if [ ! -x "${MD5_CPC_BIN}" ] && [ ! -x "${HASHCLASH_DIR}/src/md5fastcoll" ]; then
  echo "Building HashClash (./build.sh)…"
  (cd "${HASHCLASH_DIR}" && ./build.sh)
fi

########################
# 1) Create inputs (if missing)
########################
[[ -f "${PREFIX_A}" ]] || { printf "Invoice: Q3 / benign\n" > "${PREFIX_A}"; echo "Wrote ${PREFIX_A}"; }
[[ -f "${PREFIX_B}" ]] || { printf "Wire transfer: URGENT\n" > "${PREFIX_B}"; echo "Wrote ${PREFIX_B}"; }
[[ -f "${COMMON_TAIL}" ]] || { echo "No ${COMMON_TAIL}; creating 4 KiB zero tail."; truncate -s 4096 "${COMMON_TAIL}"; }

########################
# 2) Align prefixes to 64B
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
md5sum "${PDF1}" "${PDF2}" || true
echo
echo "SHA256 sums:"
sha256sum "${PDF1}" "${PDF2}" || true

########################
# 7) Expose standardized artifacts and manifest
########################
cp -f "${PDF1}" "${T1}"
cp -f "${PDF2}" "${T2}"

# (Optional) compute hashes to include in manifest (verifier ignores them anyway)
MD5_1=$(md5sum "${T1}" | awk '{print $1}')
MD5_2=$(md5sum "${T2}" | awk '{print $1}')
SHA_1=$(sha256sum "${T1}" | awk '{print $1}')
SHA_2=$(sha256sum "${T2}" | awk '{print $1}')

cat > "${MANIFEST}" <<JSON
{
  "technique": "chosen-prefix",
  "language": "free-choice",
  "artifacts": ["t1.bin","t2.bin"],
  "hashes": {
    "md5": ["${MD5_1}", "${MD5_2}"],
    "sha256": ["${SHA_1}", "${SHA_2}"]
  },
  "notes": "PDF-wrapped outputs generated via HashClash (binary preferred; fallback to scripts/cpc.sh). worklevel=${WORKLEVEL}, threads=${NTHREADS}."
}
JSON

# Print manifest to stdout (per README)
cat "${MANIFEST}"
echo
echo "Done. Outputs in: ${OUT}"

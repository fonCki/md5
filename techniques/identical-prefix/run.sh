#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Usage: ./identical_prefix_hashclash.sh
# Optional env:
#   HCDIR   - where to clone hashclash (default: $HOME/src/hashclash)
#   WORKDIR - base working directory (default: $PWD/work_identical_prefix)

: "${HCDIR:=$HOME/src/hashclash}"
: "${WORKDIR:=$PWD/work_identical_prefix}"

# ---- Common prep ----
PREFIX_TEXT="This is a very identical prefix between two files"
PDF_TEMPLATE="${WORKDIR}/yet-another-invoice-template.pdf"

echo "== identical-prefix HashClash automation =="
echo "HashClash dir: ${HCDIR}"
echo "Workdir: ${WORKDIR}"

for cmd in git python3 md5sum sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "WARNING: missing '$cmd' (install e.g. with apt)."
  fi
done

# 1) Clone/build HashClash if needed
if [[ ! -d "${HCDIR}" ]]; then
  echo "Cloning HashClash into ${HCDIR}..."
  git clone https://github.com/cr-marcstevens/hashclash "${HCDIR}"
else
  echo "Using existing HashClash at ${HCDIR}"
fi

if [[ ! -f "${HCDIR}/build.sh" ]]; then
  echo "ERROR: build.sh not found in ${HCDIR}" >&2
  exit 1
fi

MD5_FASTCOLL_BIN="${HCDIR}/src/md5fastcoll"
if [[ ! -x "${MD5_FASTCOLL_BIN}" ]]; then
  echo "Building HashClash (./build.sh)…"
  (cd "${HCDIR}" && ./build.sh)
fi

GENERIC_IPC="${HCDIR}/scripts/generic_ipc.sh"
if [[ ! -x "${GENERIC_IPC}" && ! -f "${GENERIC_IPC}" ]]; then
  echo "ERROR: ${GENERIC_IPC} not found." >&2
  exit 1
fi

# ---- Helper: run a single identical-prefix experiment in its own subdir ----
run_ipc() {
  local EXP_DIR="$1"            # sub-workdir
  local PREFIX_SRC="$2"         # source file to use as the identical prefix
  local OUT_BASENAME="$3"       # base name to use for outputs (extension decided by caller)
  local EXT="$4"                # "bin" or "pdf"

  mkdir -p "${EXP_DIR}"
  local COMMON_TAIL="${EXP_DIR}/common_tail.bin"
  local PREFIX_FILENAME="prefix_identical.bin"

  # Prepare identical prefix (copy, then pad to 64-byte multiple)
  cp -f "${PREFIX_SRC}" "${EXP_DIR}/${PREFIX_FILENAME}"
  python3 - <<PY
p = "${EXP_DIR}/${PREFIX_FILENAME}"
with open(p, "rb") as f:
    b = f.read()
pad = (64 - (len(b) % 64)) % 64
if pad:
    b += b" " * pad
with open(p, "wb") as f:
    f.write(b)
print(f"Wrote and padded prefix: {p} (len={len(b)})")
PY

  # Small common tail (optional; safe to append to PDFs after %EOF)
  [[ -f "${COMMON_TAIL}" ]] || { truncate -s 4096 "${COMMON_TAIL}"; }

  echo "Running generic_ipc in ${EXP_DIR}…"
  pushd "${EXP_DIR}" >/dev/null
  "${GENERIC_IPC}" "${PREFIX_FILENAME}" 1> /dev/null 2> /dev/null || {
    echo "ERROR: generic_ipc.sh failed; see ${EXP_DIR}/logs/" >&2
    exit 1
  }
  popd >/dev/null

  local COL_A="" COL_B=""
  if [[ -s "${EXP_DIR}/collision1.bin" && -s "${EXP_DIR}/collision2.bin" ]]; then
    COL_A="${EXP_DIR}/collision1.bin"
    COL_B="${EXP_DIR}/collision2.bin"
  else
    echo "ERROR: collision outputs not found in ${EXP_DIR}" >&2
    ls -l "${EXP_DIR}"
    exit 1
  fi

  echo
  echo "Assembled:"
  ls -l "${COL_A}" "${COL_B}"
  echo
  echo "MD5 (should be IDENTICAL):"
  md5sum "${COL_A}" "${COL_B}" || true
  echo "SHA256 (for record):"
  sha256sum "${COL_A}" "${COL_B}" || true
  echo
}

# forse prima di eseguire attacchi dovresti togliere rimasugli da run precedenti?
# sì

# -------------------------
# Experiment 1: short ASCII prefix
# -------------------------
EXP1_DIR="${WORKDIR}/exp_text"
rm -r -f "${EXP1_DIR}"
mkdir -p "${EXP1_DIR}"
TMP_ASCII_PREFIX="$(mktemp "${EXP1_DIR}/prefix.XXXX")"
printf "%s" "${PREFIX_TEXT}" > "${TMP_ASCII_PREFIX}"

echo "Experiment 1: Identical Prefix on short ASCII"
run_ipc "${EXP1_DIR}" "${TMP_ASCII_PREFIX}" "file" "bin"
rm -f "${TMP_ASCII_PREFIX}"

# -------------------------
# Experiment 2: PDF template as prefix (if present)
# -------------------------
if [[ -f "${PDF_TEMPLATE}" ]]; then
  echo "Experiment 2: Identical Prefix on PDF (${PDF_TEMPLATE})"
  EXP2_DIR="${WORKDIR}/exp_pdf"
  rm -r -f "${EXP2_DIR}"
  mkdir -p "${EXP2_DIR}"

  # Use the entire PDF as the identical prefix; we pad then append the collision blocks.
  # Most PDF readers ignore extra data after %%EOF, so files remain viewable.
  run_ipc "${EXP2_DIR}" "${PDF_TEMPLATE}" "invoice" "pdf"
else
  echo "Skipping Experiment 2: ${PDF_TEMPLATE} not found."
fi

echo "All done. See results under:"
echo "  ${WORKDIR}/exp_text"
echo "  ${WORKDIR}/exp_pdf"

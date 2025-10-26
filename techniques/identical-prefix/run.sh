#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Usage: ./identical_prefix_hashclash.sh
# Optional env:
#   HCDIR - path to clone hashclash into (default: ./hashclash)
#   WORKDIR - if you want a different workdir (default: $PWD/work_identical_prefix)

: "${HCDIR:=$HOME/src/hashclash}"
: "${WORKDIR:=$PWD/work_identical_prefix}"
PREFIX_TEXT="This is a very identical prefix between two files"
PREFIX_FILENAME="prefix_identical.bin"
COMMON_TAIL="${WORKDIR}/common_tail.bin"

echo "== identical-prefix HashClash automation =="
echo "HashClash dir: ${HCDIR}"
echo "Workdir: ${WORKDIR}"

# 0) Ensure typical build tools exist (best-effort checks)
for cmd in git python3 xxd md5sum; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "WARNING: ${cmd} not found in PATH. The script may fail; install it (e.g. apt install ${cmd})."
  fi
done

# 1) Clone HashClash if missing
if [[ ! -d "${HCDIR}" ]]; then
  echo "Cloning HashClash into ${HCDIR}..."
  git clone https://github.com/cr-marcstevens/hashclash "${HCDIR}"
else
  echo "Using existing HashClash at ${HCDIR}"
fi

# 2) Build HashClash (build.sh). If missing.
if [[ ! -f "${HCDIR}/build.sh" ]]; then
  echo "ERROR: build.sh not found in ${HCDIR}. Aborting." >&2
  exit 1
fi
echo "Running build.sh in ${HCDIR}..."
( cd "${HCDIR}" && ./build.sh )

# 3) Prepare workdir and prefix files
mkdir -p "${WORKDIR}"
echo "Preparing identical prefix file..."
# Create prefix file in current dir (so we can copy it into workdir)
TMP_PREFIX_PATH="$(mktemp -u "${PWD}/${PREFIX_FILENAME}.XXXX")"
printf "%s" "${PREFIX_TEXT}" > "${TMP_PREFIX_PATH}"

# Pad prefix to 64-byte MD5 block boundary (append spaces). Use Python to be robust.
pad_to=64
python3 - <<PY
import os
p = "${TMP_PREFIX_PATH}"
with open(p, "rb") as f:
    b = f.read()
pad = (${pad_to} - (len(b) % ${pad_to})) % ${pad_to}
if pad:
    b = b + (b" " * pad)
with open(p, "wb") as f:
    f.write(b)
print("Wrote and padded prefix to 64B block: %s (len=%d)" % (p, len(b)))
PY

# Copy identical-prefix into workdir twice under different names
cp -f "${TMP_PREFIX_PATH}" "${WORKDIR}/${}"

# Prepare a small common tail (optional) so outputs can be embedded in file format if wanted
if [[ ! -f "${COMMON_TAIL}" ]]; then
  # 4 KiB zero tail (optional)
  truncate -s 4096 "${COMMON_TAIL}"
  echo "Created common tail: ${COMMON_TAIL}"
fi

# 4) Run the chosen-prefix script inside the workdir using identical prefixes
if [[ ! -x "${HCDIR}/scripts/generic_ipc.sh" && ! -f "${HCDIR}/scripts/generic_ipc.sh" ]]; then
  echo "ERROR: ${HCDIR}/scripts/generic_ipc.sh not found. Aborting." >&2
  exit 1
fi

pushd "${WORKDIR}" >/dev/null
echo "Running ../scripts/generic_ipc.sh ${PREFIX_FILENAME}  (this may take a while)..."
# run; script variants may require certain tools; ipc.sh will produce collision files in this directory
../scripts/generic_ipc.sh "${PREFIX_FILENAME}"
popd >/dev/null

# 5) Collect collision outputs. Try common names then newest two files.
COL_A=""
COL_B=""
if [[ -f "${WORKDIR}/collision1.bin" && -f "${WORKDIR}/collision2.bin" ]]; then
  COL_A="${WORKDIR}/collision1.bin"
  COL_B="${WORKDIR}/collision2.bin"
fi

if [[ -z "${COL_A}" || -z "${COL_B}" ]]; then
  # pick newest two files (excluding the prefixes we copied)
  mapfile -t newest < <(ls -t "${WORKDIR}"/* 2>/dev/null | grep -v "${PREFIX_FILENAME}" | head -n 10)
  # Find two candidate collision files (skip tiny files)
  candidates=()
  for f in "${newest[@]:-}"; do
    # require size > 16 bytes
    if [[ -s "$f" && $(stat -c%s "$f") -gt 16 ]]; then
      candidates+=("$f")
      if [[ ${#candidates[@]} -ge 2 ]]; then break; fi
    fi
  done
  if [[ ${#candidates[@]} -ge 2 ]]; then
    COL_A="${candidates[0]}"
    COL_B="${candidates[1]}"
  fi
fi

if [[ -z "${COL_A}" || -z "${COL_B}" ]]; then
  echo "ERROR: Could not locate collision outputs in ${WORKDIR}." >&2
  echo "List of files in workdir:" >&2
  ls -l "${WORKDIR}"
  exit 1
fi

echo "Found collision outputs:"
echo "  A: ${COL_A}"
echo "  B: ${COL_B}"

FINAL_A="${WORKDIR}/fileA.bin"
FINAL_B="${WORKDIR}/fileB.bin"
cat "${WORKDIR}/${PREFIX_FILENAME}" "${COL_A}" "${COMMON_TAIL}" > "${FINAL_A}"
cat "${WORKDIR}/${PREFIX_FILENAME}" "${COL_B}" "${COMMON_TAIL}" > "${FINAL_B}"

echo "Assembled final files:"
ls -l "${FINAL_A}" "${FINAL_B}"

echo
echo "MD5 sums (expect these to be IDENTICAL for an identical-prefix collision):"
md5sum "${FINAL_A}" "${FINAL_B}" || true
echo
echo "SHA256 sums (for record):"
sha256sum "${FINAL_A}" "${FINAL_B}" || true
echo
echo "Done. Workdir: ${WORKDIR}"
echo "If sums differ, inspect the ipc output logs in ${WORKDIR}. If HashClash helper failed, ensure HashClash build completed successfully and rerun."

rm -f "${TMP_PREFIX_PATH}"

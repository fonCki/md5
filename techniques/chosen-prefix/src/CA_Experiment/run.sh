#!/usr/bin/env bash
set -euo pipefail

: "${HASHCLASH_DIR:=$HOME/src/hashclash}"
: "${WORKLEVEL:=2}"
: "${NTHREADS:=$(command -v nproc >/dev/null 2>&1 && nproc || echo 1)}"
: "${WORKDIR:=$PWD/../../out/CA_Experiment}"
: "${MD5_CPC_BIN:=${HASHCLASH_DIR}/projects/md5_chosen_prefix_collisions/cpc_md5}"

mkdir -p "${WORKDIR}"

# Check prereqs
command -v openssl >/dev/null 2>&1 || { echo "OpenSSL not found"; exit 1; }
command -v git     >/dev/null 2>&1 || { echo "git not found"; exit 1; }

# 1) One RSA key (reused)
openssl genrsa -out "${WORKDIR}/key.pem" 4096

# 2) Create cert A (self-signed) with subject A
openssl req -new -x509 -key "${WORKDIR}/key.pem" -out "${WORKDIR}/certA.pem" -days 3650 -sha256 \
  -subj "/CN=ACruelAttacker.com/O=Example Org/C=DK" \
  -set_serial 1

# 3) Create cert B (self-signed) with subject B (same key)
openssl req -new -x509 -key "${WORKDIR}/key.pem" -out "${WORKDIR}/certB.pem" -days 3650 -sha256 \
  -subj "/CN=dtu.dk/O=Technical University of Denmark/C=DK" \
  -set_serial 2

# Convert to DER at the exact paths we’ll pass to cpc_md5
PREFIX_A="${WORKDIR}/certA.der"
PREFIX_B="${WORKDIR}/certB.der"
openssl x509 -in "${WORKDIR}/certA.pem" -outform DER -out "${PREFIX_A}"
openssl x509 -in "${WORKDIR}/certB.pem" -outform DER -out "${PREFIX_B}"

# 4) Ensure HashClash is present/built
if [[ ! -d "${HASHCLASH_DIR}" ]]; then
  echo "Cloning HashClash into ${HASHCLASH_DIR}..."
  git clone https://github.com/cr-marcstevens/hashclash "${HASHCLASH_DIR}"
else
  echo "Using existing HashClash at ${HASHCLASH_DIR}"
fi

if [[ ! -f "${HASHCLASH_DIR}/build.sh" ]]; then
  echo "ERROR: build.sh not found in ${HASHCLASH_DIR}" >&2
  exit 1
fi

# Build if neither CPC nor md5_fastcoll exist yet
if [[ ! -x "${MD5_CPC_BIN}" && ! -x "${HASHCLASH_DIR}/bin/md5_fastcoll" ]]; then
  echo "Building HashClash (./build.sh)..."
  (cd "${HASHCLASH_DIR}" && ./build.sh)
else
  echo "HashClash appears to be built."
fi

# 5) Run chosen-prefix collision to produce per-file suffixes
SA="${WORKDIR}/sufA.bin"
SB="${WORKDIR}/sufB.bin"

if [[ -x "${MD5_CPC_BIN}" ]]; then
  "${MD5_CPC_BIN}" \
    --prefixfile1 "${PREFIX_A}" --prefixfile2 "${PREFIX_B}" \
    --out1 "${SA}" --out2 "${SB}" \
    --threads "${NTHREADS}" \
    --worklevel "${WORKLEVEL}"
else
  # Fallback to repo script — isolate per run; clean up on exit
  hashclash_workdir="$(mktemp -d "${HASHCLASH_DIR}/cpc_workdir.XXXXXX")"
  # trap 'echo "Cleaning up temp dir ${workdir}"; rm -rf -- "$workdir"' EXIT

  cp -f -- "${PREFIX_A}" "${PREFIX_B}" "${hashclash_workdir}/"

  (
    cd "${hashclash_workdir}"
    ../scripts/cpc.sh "${PREFIX_A}" "${PREFIX_B}" || true
  )

  if [[ -s "${PREFIX_A}.coll" && -s "${PREFIX_B}.coll" ]]; then
    mv "${PREFIX_A}.coll" "${SA}"
    mv "${PREFIX_B}.coll" "${SB}"
  else
    echo "ERROR: Collisions not found, check ${hashclash_workdir} logs." >&2
    exit 1
  fi
fi

# 6) Create final collided binaries (NOT valid DER/PEM certificates)
OUT_A="${WORKDIR}/certA_final.bin"
OUT_B="${WORKDIR}/certB_final.bin"
cat "${PREFIX_A}" "${SA}" > "${OUT_A}"
cat "${PREFIX_B}" "${SB}" > "${OUT_B}"

# 7) Show resulting hashes
echo "----------------------------------------"
echo "Collision generation complete."

MD5_A=$(md5sum "${OUT_A}" | cut -d' ' -f1)
MD5_B=$(md5sum "${OUT_B}" | cut -d' ' -f1)
SHA_A=$(sha256sum "${OUT_A}" | cut -d' ' -f1)
SHA_B=$(sha256sum "${OUT_B}" | cut -d' ' -f1)

echo "Final A MD5:     ${MD5_A}"
echo "Final B MD5:     ${MD5_B}"
echo "Final A SHA256:  ${SHA_A}"
echo "Final B SHA256:  ${SHA_B}"
echo "----------------------------------------"

if [[ "${MD5_A}" == "${MD5_B}" ]]; then
  echo "Success: MD5(outA) == MD5(outB)"
  if [[ "${SHA_A}" != "${SHA_B}" ]]; then
    echo "Success: SHA256(outA) != SHA256(outB)"
  else
    echo "Failure: SHA256(outA) == SHA256(outB)" >&2
    exit 3
  fi
else
  echo "Failure: MD5(outA) != MD5(outB)" >&2
  exit 2
fi

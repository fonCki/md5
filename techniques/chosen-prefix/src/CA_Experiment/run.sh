#!/usr/bin/env bash
set -euo pipefail

: "${HASHCLASH_DIR:=$HOME/src/hashclash}"
: "${WORKLEVEL:=2}"
: "${NTHREADS:=$(command -v nproc >/dev/null 2>&1 && nproc || echo 1)}"
: "${WORKDIR:=$PWD/../../out/CA_Experiment_2}"
: "${MD5_CPC_BIN:=${HASHCLASH_DIR}/projects/md5_chosen_prefix_collisions/cpc_md5}"

read -r -p "Do you want a dry run? [Y/n] " response

case "$response" in
    [nN][oO]|[nN])
        DRY=0
        ;;
    *)
        DRY=1
        ;;
esac


mkdir -p "${WORKDIR}"

# Check prereqs
command -v openssl >/dev/null 2>&1 || { echo "OpenSSL not found"; exit 1; }
command -v git     >/dev/null 2>&1 || { echo "git not found"; exit 1; }

PREFIX_A="${WORKDIR}/requestA_og.der"
PREFIX_B="${WORKDIR}/requestB_og.der"

#  Ensure HashClash is present/built
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

#  Run chosen-prefix collision to produce per-file suffixes
SA="${WORKDIR}/requestA.der"
SB="${WORKDIR}/requestB.der"

generate_new_input() {
  #  One RSA key (reused)
  openssl genrsa -out "${WORKDIR}/key.pem" 4096

  #  Richiesta di A non firmata
  openssl req -new -key "${WORKDIR}/key.pem" -out "${WORKDIR}/requestA_og.der" \
    -subj "/CN=ACruelAttacker.com/O=Example Org/C=DK" \
    -outform DER

  #  Richiesta di B non firmata
  openssl req -new -key "${WORKDIR}/key.pem" -out "${WORKDIR}/requestB_og.der" \
    -subj "/CN=dtu.dk/O=Technical University of Denmark/C=DK" \
    -set_serial 2 \
    -outform DER
}

hashclash() {
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
}

if [[ $DRY -eq 0 ]]; then
  generate_new_input
  hashclash
else
  echo "Dry run selected, using pre-existing collision ."
fi


# 7) Show resulting hashes
echo "----------------------------------------"
echo "Collision generation complete."

MD5_A=$(md5sum "${SA}" | cut -d' ' -f1)  # UNBOUND VARIABLE! OUT_A not defined
MD5_B=$(md5sum "${SB}" | cut -d' ' -f1)
SHA_A=$(sha256sum "${SA}" | cut -d' ' -f1)
SHA_B=$(sha256sum "${SB}" | cut -d' ' -f1)

echo "Final A MD5:     ${MD5_A}"
echo "Final B MD5:     ${MD5_B}"
echo "Final A SHA256:  ${SHA_A}"
echo "Final B SHA256:  ${SHA_B}"
echo "----------------------------------------"

echo "Now I have two different requests with the same MD5 Hash."
echo "Theoretically a CA could sign the benign one (A) and the signature would also be valid for the malicious one (B)."
echo "However, openssl ignores what is after the end of file and thus invalidates our attack. Only a naive CA could be tricked this way."

openssl req -text -in "${SA}" -inform DER
openssl req -text -in "${SB}" -inform DER


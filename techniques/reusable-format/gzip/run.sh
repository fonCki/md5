#!/usr/bin/env bash
# Reusable format MD5 collision demo (GZIP .tar.gz)
# Contract: run with --out-dir <PATH> and produce:
#   <PATH>/collision1.tar.gz, <PATH>/collision2.tar.gz, <PATH>/manifest.json
# (manifest lists the two real artifacts; no t1.bin/t2.bin anymore)
set -euo pipefail

# ---- parse args -------------------------------------------------------------
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -n "${OUT}" ]] || { echo "missing --out-dir"; exit 2; }

# ---- resolve paths ----------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SELF_DIR="${SCRIPT_DIR}"                                 # techniques/reusable-format/gzip
SRC_DIR="${SELF_DIR}/src"
ASSETS_DIR="${SRC_DIR}/assets"
PFX_DIR="${ASSETS_DIR}/prefixes"

# ---- sanity checks (Ubuntu 24.04 defaults) ---------------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1"; exit 3; }; }
need python3; need tar; need gzip; need md5sum; need sha256sum; need diff

[[ -f "${SRC_DIR}/gz.py" ]] || { echo "missing ${SRC_DIR}/gz.py"; exit 4; }
[[ -f "${PFX_DIR}/prefix1.gz" && -f "${PFX_DIR}/prefix2.gz" ]] || { echo "missing prefixes in ${PFX_DIR}"; exit 4; }
[[ -f "${ASSETS_DIR}/benign/treeA/README.txt" ]]    || { echo "missing benign README"; exit 4; }
[[ -f "${ASSETS_DIR}/malicious/treeB/README.txt" ]] || { echo "missing malicious README"; exit 4; }

# ---- colors (disable if not a TTY or NO_COLOR is set) ----------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
ok()   { printf "%b✓%b %s\n" "$GREEN" "$RESET" "$1"; }
warn() { printf "%b•%b %s\n" "$YELLOW" "$RESET" "$1"; }
bad()  { printf "%b✗%b %s\n" "$RED" "$RESET" "$1"; }

# ---- prepare out dir --------------------------------------------------------
mkdir -p "${OUT}"
rm -f "${OUT}/manifest.json" \
      "${OUT}/collision1.tar.gz" "${OUT}/collision2.tar.gz"
rm -rf "${OUT}/extract1" "${OUT}/extract2"
: > "${OUT}/verification.txt"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

# ---- step 1: create payload tarballs ---------------------------------------
tar -C "${ASSETS_DIR}/benign"    -cf "${WORKDIR}/A.tar" treeA
tar -C "${ASSETS_DIR}/malicious" -cf "${WORKDIR}/B.tar" treeB
GZIP=-n gzip -9 "${WORKDIR}/A.tar"
GZIP=-n gzip -9 "${WORKDIR}/B.tar"

# ---- step 2: run generator with prefixes (expects prefixes in CWD) ---------
cp "${SRC_DIR}/gz.py"      "${WORKDIR}/gz.py"
cp "${PFX_DIR}/prefix1.gz" "${WORKDIR}/prefix1.gz"
cp "${PFX_DIR}/prefix2.gz" "${WORKDIR}/prefix2.gz"

pushd "${WORKDIR}" >/dev/null
python3 ./gz.py A.tar.gz B.tar.gz 1>&2         # prints "Success!" + MD5 to stderr
popd >/dev/null

# ---- step 3: copy results, verify, extract ---------------------------------
cp "${WORKDIR}/coll-1.gz" "${OUT}/collision1.tar.gz"
cp "${WORKDIR}/coll-2.gz" "${OUT}/collision2.tar.gz"

# hashes for the tar.gz members
MD5_LINE="$(md5sum    "${OUT}/collision1.tar.gz" "${OUT}/collision2.tar.gz")"
SHA_LINE="$(sha256sum "${OUT}/collision1.tar.gz" "${OUT}/collision2.tar.gz")"

gzip -t "${OUT}/collision1.tar.gz" && I1="OK" || I1="FAIL"
gzip -t "${OUT}/collision2.tar.gz" && I2="OK" || I2="FAIL"

mkdir -p "${OUT}/extract1" "${OUT}/extract2"
tar -xzf "${OUT}/collision1.tar.gz" -C "${OUT}/extract1"
tar -xzf "${OUT}/collision2.tar.gz" -C "${OUT}/extract2"

# locate readmes and compute their metadata (portable size with wc -c)
R1="${OUT}/extract1/treeA/README.txt"
R2="${OUT}/extract2/treeB/README.txt"
S1=$(wc -c < "${R1}")
S2=$(wc -c < "${R2}")
MR1=$(md5sum "${R1}" | awk '{print $1}')
MR2=$(md5sum "${R2}" | awk '{print $1}')
SR1=$(sha256sum "${R1}" | awk '{print $1}')
SR2=$(sha256sum "${R2}" | awk '{print $1}')

# diff (non-zero means 'different', which we expect)
set +e
DIFF_OUT="$(diff -r "${OUT}/extract1" "${OUT}/extract2")"
DIFF_CODE=$?
set -e

# ---- step 4: manifest with REAL artifacts (no .bin) ------------------------
cat > "${OUT}/manifest.json" <<'JSON'
{
  "technique": "reusable",
  "language": "bash+python-stdlib",
  "artifacts": ["collision1.tar.gz", "collision2.tar.gz"],
  "notes": "GZIP (.tar.gz) reusable-collision: MD5 equal, SHA-256 different, gzip -t OK, extracted trees differ."
}
JSON

# ---- step 5: print manifest, then a colorized summary ----------------------
cat "${OUT}/manifest.json"

echo >> "${OUT}/verification.txt"
{
  echo "== HASHES =="
  echo "${MD5_LINE}"
  echo "${SHA_LINE}"
  echo
  echo "== INTEGRITY =="
  echo "collision1: ${I1}"
  echo "collision2: ${I2}"
  echo
  echo "== README METADATA =="
  echo "README A path: ${R1}"
  echo "README B path: ${R2}"
  echo "Size A: ${S1} bytes"
  echo "Size B: ${S2} bytes"
  echo "MD5 A:  ${MR1}"
  echo "MD5 B:  ${MR2}"
  echo "SHA256 A: ${SR1}"
  echo "SHA256 B: ${SR2}"
  echo
  echo "== README CONTENT (first 200 chars each) =="
  head -c 200 "${R1}" ; echo
  head -c 200 "${R2}" ; echo
  echo
  echo "== DIFF (extract1 vs extract2) =="
  if [[ ${DIFF_CODE} -ne 0 ]]; then
    echo "${DIFF_OUT}"
  else
    echo "(no differences — unexpected for this demo)"
  fi
} >> "${OUT}/verification.txt"

# pretty stdout summary (color)
echo
echo "${BOLD}Reusable MD5 Collision — GZIP (.tar.gz)${RESET}"
[[ ${I1} == "OK" && ${I2} == "OK" ]] && ok "gzip -t: both archives OK" || bad "gzip -t: integrity issue"
# MD5 equality check
MD5_A=$(echo "${MD5_LINE}" | awk 'NR==1{print $1}')
MD5_B=$(echo "${MD5_LINE}" | awk 'NR==2{print $1}')
if [[ "${MD5_A}" == "${MD5_B}" ]]; then ok "MD5(collision1) == MD5(collision2) = ${MD5_A}"
else bad "MD5 differ (unexpected)"; fi
# SHA-256 inequality check
SHA_A=$(echo "${SHA_LINE}" | awk 'NR==1{print $1}')
SHA_B=$(echo "${SHA_LINE}" | awk 'NR==2{print $1}')
if [[ "${SHA_A}" != "${SHA_B}" ]]; then ok "SHA256 differs (good): ${SHA_A} vs ${SHA_B}"
else bad "SHA256 identical (unexpected)"; fi

# README details
echo
echo "${BLUE}${BOLD}README A${RESET} (${S1} bytes)"
echo "MD5: ${MR1}"
echo "SHA256: ${SR1}"
printf "%b%s%b\n" "$DIM" "$(head -c 200 "${R1}")" "$RESET"
echo
echo "${BLUE}${BOLD}README B${RESET} (${S2} bytes)"
echo "MD5: ${MR2}"
echo "SHA256: ${SR2}"
printf "%b%s%b\n" "$DIM" "$(head -c 200 "${R2}")" "$RESET"
echo
if [[ ${DIFF_CODE} -ne 0 ]]; then ok "Extracted trees differ (as intended)"
else bad "Extracted trees are identical (unexpected)"; fi

echo
warn "Full log saved to: ${OUT}/verification.txt"
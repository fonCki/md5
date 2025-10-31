#!/usr/bin/env bash
# Author: Alfonso Pedro Ridao (s243942)
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
SELF_DIR="${SCRIPT_DIR}"
SRC_DIR="${SELF_DIR}/src"
IN_DIR="${SRC_DIR}/assets/inputs"
PAY_DIR="${SRC_DIR}/assets/payloads"

# ---- tiny utilities ---------------------------------------------------------
has() { command -v "$1" >/dev/null 2>&1; }
need(){ has "$1" || { echo "missing dependency: $1"; exit 3; }; }

# cross-platform hash helpers (GNU or macOS)
# nota: verificar en linux y mac
hash_md5(){
  if   has md5sum; then md5sum "$@"
  elif has md5;    then md5 -r "$@"
  else echo "missing md5sum/md5"; exit 3; fi
}

hash_sha256(){
  if   has sha256sum; then sha256sum "$@"
  elif has shasum;    then shasum -a 256 "$@"
  else echo "missing sha256sum/shasum"; exit 3; fi
}

# attempt to install jpegtran if missing (ubuntu apt or macOS Homebrew)
# TODO revisar si funciona en todas las distros
ensure_jpegtran(){
  if has jpegtran; then return 0; fi
  echo "jpegtran not found — attempting installation..."
  if has apt-get; then
    # Ubuntu/Debian
    if has sudo; then
      sudo apt-get update -y && sudo apt-get install -y libjpeg-turbo-progs || {
        echo "Failed to install jpegtran via apt-get."; exit 3; }
    else
      echo "sudo not available; please install: apt-get update && apt-get install -y libjpeg-turbo-progs"
      exit 3
    fi
  elif has brew; then
    # macOS
    brew install jpeg || brew install jpeg-turbo || {
      echo "Failed to install jpeg/jpeg-turbo via Homebrew."; exit 3; }
  else
    echo "No known package manager. Please install jpegtran (Ubuntu: libjpeg-turbo-progs; macOS: brew install jpeg)."
    exit 3
  fi
  has jpegtran || { echo "jpegtran still missing after install attempt."; exit 3; }
}

# ---- colors -----------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

ok()   { printf "%b✓%b %s\n" "$GREEN" "$RESET" "$1"; }
bad(){ printf "%b✗%b %s\n" "$RED" "$RESET" "$1"; }
warn() { printf "%b•%b %s\n" "$YELLOW" "$RESET" "$1"; }

# ---- sanity checks (auto-bootstrap jpegtran) --------------------------------
need python3
ensure_jpegtran

[[ -f "${SRC_DIR}/jpg.py" ]]           || { echo "missing ${SRC_DIR}/jpg.py"; exit 4; }
[[ -f "${IN_DIR}/messi.jpg" ]]         || { echo "missing ${IN_DIR}/messi.jpg"; exit 4; }
[[ -f "${IN_DIR}/ronaldo.jpg" ]]       || { echo "missing ${IN_DIR}/ronaldo.jpg"; exit 4; }
[[ -f "${PAY_DIR}/jpg1.bin" ]]         || { echo "missing ${PAY_DIR}/jpg1.bin"; exit 4; }
[[ -f "${PAY_DIR}/jpg2.bin" ]]         || { echo "missing ${PAY_DIR}/jpg2.bin"; exit 4; }

# ---- prepare out dir --------------------------------------------------------
mkdir -p "${OUT}"
rm -f "${OUT}/manifest.json" "${OUT}/collision1.jpg" "${OUT}/collision2.jpg"
: > "${OUT}/verification.txt"

WORKDIR="$(mktemp -d)"
cleanup(){ rm -rf "${WORKDIR}"; }
trap cleanup EXIT

# ---- stage inputs & preprocess to progressive scans -------------------------
# nota: copiar imgs originales primero
cp "${IN_DIR}/messi.jpg"   "${WORKDIR}/a.jpg"
cp "${IN_DIR}/ronaldo.jpg" "${WORKDIR}/b.jpg"

# convert to progressive scan (required for collision insertion)
jpegtran -copy all -optimize -progressive "${WORKDIR}/a.jpg" > "${WORKDIR}/a_prog.jpg"
jpegtran -copy all -optimize -progressive "${WORKDIR}/b.jpg" > "${WORKDIR}/b_prog.jpg"

# ---- stage generator & payloads, then run ----------------------------------
cp "${SRC_DIR}/jpg.py"     "${WORKDIR}/jpg.py"
cp "${PAY_DIR}/jpg1.bin"   "${WORKDIR}/jpg1.bin"
cp "${PAY_DIR}/jpg2.bin"   "${WORKDIR}/jpg2.bin"

pushd "${WORKDIR}" >/dev/null
python3 ./jpg.py a_prog.jpg b_prog.jpg
popd >/dev/null

# ---- find outputs (handles both naming styles) -----------------------------
O1=""; O2=""
if   [[ -f "${WORKDIR}/collision1.jpg" && -f "${WORKDIR}/collision2.jpg" ]]; then
  O1="collision1.jpg"; O2="collision2.jpg"
elif [[ -f "${WORKDIR}/coll-1.jpg" && -f "${WORKDIR}/coll-2.jpg" ]]; then
  O1="coll-1.jpg"; O2="coll-2.jpg"
else
  echo "jpg.py did not produce expected outputs. Workdir listing:" >&2
  ls -la "${WORKDIR}" >&2
  exit 5
fi

# ---- copy results & verify --------------------------------------------------
cp "${WORKDIR}/${O1}" "${OUT}/collision1.jpg"
cp "${WORKDIR}/${O2}" "${OUT}/collision2.jpg"

# calc hashes
MD5_LINE="$(hash_md5     "${OUT}/collision1.jpg" "${OUT}/collision2.jpg")"
SHA_LINE="$(hash_sha256  "${OUT}/collision1.jpg" "${OUT}/collision2.jpg")"
S1=$(wc -c < "${OUT}/collision1.jpg")
S2=$(wc -c < "${OUT}/collision2.jpg")

# ---- manifest (real artifacts) ---------------------------------------------
cat > "${OUT}/manifest.json" <<'JSON'
{
  "technique": "reusable",
  "language": "bash+python-stdlib",
  "artifacts": ["collision1.jpg", "collision2.jpg"],
  "notes": "JPEG reusable-collision from two user photos (with prebuilt payload blocks): MD5 equal, SHA-256 different; both images open normally and show different visuals."
}
JSON

# ---- log & pretty summary ---------------------------------------------------
{
  echo "== HASHES =="; echo "${MD5_LINE}"; echo "${SHA_LINE}";
  echo; echo "== SIZES =="; echo "collision1.jpg: ${S1} bytes"; echo "collision2.jpg: ${S2} bytes";
  echo; echo "== NOTE =="; echo "Open both images to visually confirm different pictures (Messi vs Ronaldo).";
} >> "${OUT}/verification.txt"

cat "${OUT}/manifest.json"

echo
echo "${BOLD}Reusable MD5 Collision — JPEG (your inputs)${RESET}"
MD5_A=$(echo "${MD5_LINE}" | awk 'NR==1{print $1}'); MD5_B=$(echo "${MD5_LINE}" | awk 'NR==2{print $1}')
[[ "${MD5_A}" == "${MD5_B}" ]] && ok "MD5(collision1) == MD5(collision2) = ${MD5_A}" || bad "MD5 differ (unexpected)"
SHA_A=$(echo "${SHA_LINE}" | awk 'NR==1{print $1}'); SHA_B=$(echo "${SHA_LINE}" | awk 'NR==2{print $1}')
[[ "${SHA_A}" != "${SHA_B}" ]] && ok "SHA256 differs (good): ${SHA_A} vs ${SHA_B}"   || bad "SHA256 identical (unexpected)"
echo
echo "${BLUE}${BOLD}Manual step${RESET}: open the two files and verify they display different pictures:"
echo "  ${OUT}/collision1.jpg"
echo "  ${OUT}/collision2.jpg"
echo
warn "Full log saved to: ${OUT}/verification.txt"

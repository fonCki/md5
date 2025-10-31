#!/usr/bin/env bash
# Author: Alfonso Pedro Ridao (s243942)
# reusable format collision demo for PDF
# produces collision1.pdf, collision2.pdf, manifest.json

set -euo pipefail

# parse args
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -n "${OUT}" ]] || { echo "missing --out-dir"; exit 2; }


# resolve paths
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SELF_DIR="${SCRIPT_DIR}"
SRC_DIR="${SELF_DIR}/src"
IN_DIR="${SRC_DIR}/assets/inputs"
PAY_DIR="${SRC_DIR}/assets/payloads"

# tiny utils
has(){ command -v "$1" >/dev/null 2>&1; }
need(){ has "$1" || { echo "missing dependency: $1"; exit 3; }; }

# nota: hash helpers para GNU y macOS
hash_md5_one(){
  if has md5sum; then md5sum "$1" | awk '{print $1}'
  elif has md5; then md5 -r "$1" | awk '{print $1}'
  else echo "missing md5sum/md5"; exit 3; fi
}
hash_sha256_one(){
  if has sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif has shasum; then shasum -a 256 "$1" | awk '{print $1}'
  else echo "missing sha256sum/shasum"; exit 3; fi
}
# sha256 for stream from stdin
hash_sha256_stream(){
  if has sha256sum; then sha256sum - | awk '{print $1}'
  elif has shasum; then shasum -a 256 - | awk '{print $1}'
  else echo "missing sha256sum/shasum"; exit 3; fi
}

# auto-bootstrap (tries apt-get/brew)
ensure_mutool(){
  if has mutool; then return 0; fi
  echo "mutool not found - trying to install..."
  if has apt-get; then
    has sudo && sudo apt-get update -y && sudo apt-get install -y mupdf-tools || {
      echo "Install MuPDF manually: sudo apt-get install -y mupdf-tools"; exit 3; }
  elif has brew; then
    brew install mupdf || { echo "Install MuPDF manually: brew install mupdf"; exit 3; }
  else
    echo "No known package manager. Please install MuPDF (mutool) first."; exit 3;
  fi
}
# TODO revisar si funciona en todas las distros
ensure_pdftotext(){
  if has pdftotext; then return 0; fi
  echo "pdftotext not found - trying to install..."
  if has apt-get; then
    has sudo && sudo apt-get update -y && sudo apt-get install -y poppler-utils || {
      echo "Install pdftotext manually: sudo apt-get install -y poppler-utils"; exit 3; }
  elif has brew; then
    brew install poppler || { echo "Install pdftotext manually: brew install poppler"; exit 3; }
  else
    echo "No known package manager. Please install pdftotext (Poppler) first."; exit 3;
  fi
}

# colors
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
ok(){ printf "%b✓%b %s\n" "$GREEN" "$RESET" "$1"; }
bad(){ printf "%b✗%b %s\n" "$RED" "$RESET" "$1"; }
warn(){ printf "%b•%b %s\n" "$YELLOW" "$RESET" "$1"; }

# sanity checks
need python3
ensure_mutool
ensure_pdftotext

[[ -f "${SRC_DIR}/pdf.py" ]] || { echo "missing ${SRC_DIR}/pdf.py"; exit 4; }
[[ -f "${PAY_DIR}/pdf1.bin" ]] || { echo "missing ${PAY_DIR}/pdf1.bin"; exit 4; }
[[ -f "${PAY_DIR}/pdf2.bin" ]] || { echo "missing ${PAY_DIR}/pdf2.bin"; exit 4; }
[[ -f "${IN_DIR}/brownies_recipe.pdf" ]] || { echo "missing ${IN_DIR}/brownies_recipe.pdf"; exit 4; }
[[ -f "${IN_DIR}/brownies_recipe_with_poison.pdf" ]] || { echo "missing ${IN_DIR}/brownies_recipe_with_poison.pdf"; exit 4; }

# prep out dir
mkdir -p "${OUT}"
rm -f "${OUT}/manifest.json" \
      "${OUT}/collision1.pdf" "${OUT}/collision2.pdf"
: > "${OUT}/verification.txt"

WORKDIR="$(mktemp -d)"
cleanup(){ rm -rf "${WORKDIR}"; }
trap cleanup EXIT

# stage & normalize inputs
cp "${IN_DIR}/brownies_recipe.pdf" "${WORKDIR}/A.pdf"
cp "${IN_DIR}/brownies_recipe_with_poison.pdf" "${WORKDIR}/B.pdf"
mutool clean -gg "${WORKDIR}/A.pdf" "${WORKDIR}/A.norm.pdf"
mutool clean -gg "${WORKDIR}/B.pdf" "${WORKDIR}/B.norm.pdf"


# nota: copiar collider y payloads
cp "${SRC_DIR}/pdf.py" "${WORKDIR}/pdf.py"
cp "${PAY_DIR}/pdf1.bin" "${WORKDIR}/pdf1.bin"
cp "${PAY_DIR}/pdf2.bin" "${WORKDIR}/pdf2.bin"

# run collider (two-arg mode)
pushd "${WORKDIR}" >/dev/null
( python3 ./pdf.py A.norm.pdf B.norm.pdf ) > run.out 2> run.err || true
O1=""; O2=""
if [[ -f collision1.pdf && -f collision2.pdf ]]; then
  O1="collision1.pdf"; O2="collision2.pdf"
elif [[ -f coll-1.pdf && -f coll-2.pdf ]]; then
  O1="coll-1.pdf"; O2="coll-2.pdf"
else
  echo "pdf.py ran but outputs not found." >&2
  echo "---- run.out ----"; sed -n '1,80p' run.out 2>/dev/null || true
  echo "---- run.err ----"; sed -n '1,120p' run.err 2>/dev/null || true
  echo "Workdir listing:"; ls -la
  popd >/dev/null
  exit 5
fi
popd >/dev/null

# copy results & verify
cp "${WORKDIR}/${O1}" "${OUT}/collision1.pdf"
cp "${WORKDIR}/${O2}" "${OUT}/collision2.pdf"

MD5_A=$(hash_md5_one "${OUT}/collision1.pdf")
MD5_B=$(hash_md5_one "${OUT}/collision2.pdf")
SHA_A=$(hash_sha256_one "${OUT}/collision1.pdf")
SHA_B=$(hash_sha256_one "${OUT}/collision2.pdf")
S1=$(wc -c < "${OUT}/collision1.pdf")
S2=$(wc -c < "${OUT}/collision2.pdf")

# streamed semantic check
TXT_SHA_A=$(pdftotext "${OUT}/collision1.pdf" - | hash_sha256_stream || echo "NA")
TXT_SHA_B=$(pdftotext "${OUT}/collision2.pdf" - | hash_sha256_stream || echo "NA")
SNIP_A=$(pdftotext "${OUT}/collision1.pdf" - | head -c 160 | tr '\n' ' ' || true)
SNIP_B=$(pdftotext "${OUT}/collision2.pdf" - | head -c 160 | tr '\n' ' ' || true)

# manifest
cat > "${OUT}/manifest.json" <<'JSON'
{
  "technique": "reusable",
  "language": "bash+python-stdlib",
  "artifacts": ["collision1.pdf", "collision2.pdf"],
  "notes": "PDF reusable-collision: MD5 equal, SHA-256 different; opens in common viewers; pdftotext text-hashes differ."
}
JSON

# log & summary
{
  echo "== HASHES ==";
  printf "MD5    collision1.pdf: %s\n" "${MD5_A}"
  printf "MD5    collision2.pdf: %s\n" "${MD5_B}"
  printf "SHA256 collision1.pdf: %s\n" "${SHA_A}"
  printf "SHA256 collision2.pdf: %s\n" "${SHA_B}"
  echo
  echo "== TEXT HASH CHECK (pdftotext | SHA256 of text) ==";
  printf "textSHA collision1: %s\n" "${TXT_SHA_A}"
  printf "textSHA collision2: %s\n" "${TXT_SHA_B}"
  echo
  echo "== SHORT TEXT SNIPPETS (first 160 chars) ==";
  echo "c1: ${SNIP_A}"
  echo "c2: ${SNIP_B}"
} >> "${OUT}/verification.txt"

# stdout summary
cat "${OUT}/manifest.json"
echo
echo "${BOLD}Reusable MD5 Collision — PDF${RESET}"
[[ "${MD5_A}" == "${MD5_B}" ]] && ok "MD5(collision1) == MD5(collision2) = ${MD5_A}" || bad "MD5 differ (unexpected)"
[[ "${SHA_A}" != "${SHA_B}" ]] && ok "SHA256 differs (good): ${SHA_A} vs ${SHA_B}" || bad "SHA256 identical (unexpected)"
if [[ "${TXT_SHA_A}" != "${TXT_SHA_B}" ]]; then ok "pdftotext text-hashes differ (semantic difference)"; else warn "pdftotext text-hashes identical (maybe only graphical diff)"; fi
echo
warn "Compact log saved to: ${OUT}/verification.txt"
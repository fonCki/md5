#!/usr/bin/env bash
# Author: Alfonso Pedro Ridao (s243942)
# Identical-Prefix MD5 collision

# Flow:
#   1) Skip if outputs already exist
#   2) Ensure HashClash (auto-bootstrap into ./.vendor/hashclash if missing)
#   3) Use md5_fastcoll to generate a binary-colliding pair, then append a common
#      readable suffix to get two .txt files that still collide under MD5

set -euo pipefail

# ---------- args ----------
OUT=""
PREFIX="02232_Applied_Cryptography_Fall_2025"
APPENDIX_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT="$2"; shift 2;;
    --prefix) PREFIX="$2"; shift 2;;
    --appendix) APPENDIX_FILE="$2"; shift 2;;
    -h|--help) echo "Usage: $0 --out-dir DIR [--prefix STR] [--appendix FILE]"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -n "${OUT}" ]] || { echo "missing --out-dir"; exit 2; }


# ---------- paths ----------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SELF_DIR="${SCRIPT_DIR}" # techniques/identical-prefix
HC="${SELF_DIR}/.vendor/hashclash"
BIN="${HC}/bin"
SCRIPTS="${HC}/scripts"

mkdir -p "${OUT}"
RES_A="${OUT}/result_A.txt"
RES_B="${OUT}/result_B.txt"
SOLVER_LOG="${OUT}/solver.log"
VERIF="${OUT}/verification.txt"

# ---------- colors ----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RESET=""
fi
ok(){ printf "%b✓%b %s\n" "$GREEN" "$RESET" "$1"; }
warn(){ printf "%b•%b %s\n" "$YELLOW" "$RESET" "$1"; }

# ---------- hash helpers (macOS/Linux) ----------
# TODO revisar si funciona en todas las distros
hash_md5(){
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$@"
  else
    md5 -r "$@"
  fi
}

hash_sha256(){
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

# ---------- 1) skip if already done ----------
if [[ -f "${RES_A}" && -f "${RES_B}" ]]; then
  warn "results already exist; skipping:"
  echo "  ${RES_A}"
  echo "  ${RES_B}"
  exit 0
fi

# clean leftovers from partial runs
rm -f "${OUT}/manifest.json" "${OUT}/c1.bin" "${OUT}/c2.bin" \
      "${OUT}/prefix.txt" "${OUT}/appendix.txt" \
      "${RES_A}" "${RES_B}" "${SOLVER_LOG}" "${VERIF}"
: > "${VERIF}"


# ---------- 2) ensure HashClash ----------
ensure_hashclash() {
  if [[ -x "${BIN}/md5_fastcoll" ]]; then
    return 0
  fi
  if [[ -x "${SELF_DIR}/src/bootstrap_hashclash.sh" ]]; then
    echo "[-] HashClash not found. Bootstrapping into: ${HC}"
    bash "${SELF_DIR}/src/bootstrap_hashclash.sh"
  fi
  if [[ ! -x "${BIN}/md5_fastcoll" ]]; then
    echo "[!] md5_fastcoll still not present after bootstrap. Aborting." | tee -a "${SOLVER_LOG}"
    exit 4
  fi
}
ensure_hashclash

# expose tools to PATH
export PATH="${BIN}:$PATH"

# portable CPU count
if command -v nproc >/dev/null 2>&1; then
  export NTHREADS="$(nproc)"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  export NTHREADS="$(sysctl -n hw.ncpu)"
else
  export NTHREADS=2
fi

# ---------- 3) identical-prefix collision via md5_fastcoll ----------
# prefer md5_fastcoll (HashClash tool name). fallback to PATH
FC=""
if [[ -x "${BIN}/md5_fastcoll" ]]; then
  FC="${BIN}/md5_fastcoll"
elif command -v md5_fastcoll >/dev/null 2>&1; then
  FC="$(command -v md5_fastcoll)"
fi

if [[ -n "${FC}" ]]; then
  echo "[*] Using md5_fastcoll (identical-prefix) ..." | tee -a "${SOLVER_LOG}"
  # make sure OUT exists and write the prefix
  mkdir -p "${OUT}"
  printf '%s' "${PREFIX}" > "${OUT}/prefix.txt"

  # nota: generar la colision binaria
  "${FC}" -p "${OUT}/prefix.txt" -o "${OUT}/c1.bin" "${OUT}/c2.bin" 2>&1 | tee -a "${SOLVER_LOG}"
else
  echo "[!] md5_fastcoll not available; aborting to avoid Linux-only pipeline." | tee -a "${SOLVER_LOG}"
  exit 5
fi

# verify (binary stage)
{
  echo "== IPC (binary pair) =="
  echo "Prefix (ASCII): ${PREFIX}"
  echo "Sizes:"; wc -c "${OUT}/c1.bin" "${OUT}/c2.bin"
  echo "MD5:"; hash_md5 "${OUT}/c1.bin" "${OUT}/c2.bin"
  echo "SHA-256:"; hash_sha256 "${OUT}/c1.bin" "${OUT}/c2.bin"
  echo "First diffs:"; cmp -l "${OUT}/c1.bin" "${OUT}/c2.bin" | head || true
} >> "${VERIF}"

# append a common readable suffix → final .txt pair
if [[ -n "${APPENDIX_FILE}" ]]; then
  cp "${APPENDIX_FILE}" "${OUT}/appendix.txt"
else
  cat > "${OUT}/appendix.txt" <<'TXT'
--- Appendix (readable) ---
Course: 02232 Applied Cryptography (Fall 2025)
Note: Appending the SAME bytes to both files preserves the MD5 collision (Merkle–Damgård).
TXT
fi

cat "${OUT}/c1.bin" "${OUT}/appendix.txt" > "${RES_A}"
cat "${OUT}/c2.bin" "${OUT}/appendix.txt" > "${RES_B}"

# final verification
{
  echo
  echo "== IPC (.txt pair after common suffix) =="
  echo "Sizes:"; wc -c "${RES_A}" "${RES_B}"
  echo "MD5:"; hash_md5 "${RES_A}" "${RES_B}"
  echo "SHA-256:"; hash_sha256 "${RES_A}" "${RES_B}"
} >> "${VERIF}"

# manifest + summary
cat > "${OUT}/manifest.json" <<'JSON'
{
  "technique": "identical-prefix",
  "language": "bash",
  "artifacts": ["result_A.txt", "result_B.txt"],
  "notes": "MD5 equal, SHA-256 different. Identical-prefix with common readable suffix."
}
JSON

cat "${OUT}/manifest.json"
echo
echo "${BOLD}Identical-Prefix MD5 Collision${RESET}"
ok  "Binary pair: c1.bin / c2.bin"
ok  "Final colliding artifacts: result_A.txt / result_B.txt"
warn "Log: ${SOLVER_LOG}"
warn "Verification: ${VERIF}"

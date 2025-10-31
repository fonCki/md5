#!/usr/bin/env bash
# clean out/ keeping .gitkeep
set -euo pipefail

OUT=""
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

# default to ./out next to this script
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ -n "${OUT}" ]] || OUT="${SELF_DIR}/out"
mkdir -p "${OUT}"


case "${OUT}" in
  "${SELF_DIR}"| "${SELF_DIR}/"* ) : ;;
  * ) echo "Refusing to clean outside technique dir: ${OUT}" >&2; exit 3;;
esac

KEEP="${OUT}/.gitkeep"
TMP_KEEP="$(mktemp -t keep.XXXXXX || true)"
[[ -f "${KEEP}" ]] && cp -f "${KEEP}" "${TMP_KEEP}" || true

# remove everything except .gitkeep (portable glob + filter)
shopt -s dotglob nullglob
TO_DELETE=("${OUT}"/*)
PRUNED=()
for p in "${TO_DELETE[@]:-}"; do
  [[ "$(basename "$p")" == ".gitkeep" ]] && continue
  PRUNED+=("$p")
done

if (( ${#PRUNED[@]} )); then
  if (( DRY )); then
    printf 'Would remove %d item(s) from %s:\n' "${#PRUNED[@]}" "${OUT}"
    printf '  %s\n' "${PRUNED[@]}"
  else
    rm -rf -- "${PRUNED[@]}"
  fi
fi

# restore or recreate .gitkeep
if [[ -f "${TMP_KEEP}" ]]; then
  mv -f "${TMP_KEEP}" "${KEEP}" || :
else
  : > "${KEEP}"
fi

(( DRY )) && echo "DRY RUN complete for ${OUT}" || echo "Cleaned ${OUT}"

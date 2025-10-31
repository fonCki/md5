#!/usr/bin/env bash
# Author: Alfonso Pedro Ridao (s243942)
# clean all out/ dirs but keep .gitkeep
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
DRY=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY=1; fi

run_local_clean() {
  local tech_dir="$1"
  local out_dir="${tech_dir}/out"
  [[ -d "${out_dir}" ]] || return 0

  if [[ -x "${tech_dir}/clean.sh" ]]; then
    # use tech's own clean script if available
    if (( DRY )); then
      "${tech_dir}/clean.sh" --out-dir "${out_dir}" --dry-run
    else
      "${tech_dir}/clean.sh" --out-dir "${out_dir}"
    fi
  else
    # fallback: generic clean
    local keep="${out_dir}/.gitkeep"
    local tmp_keep; tmp_keep="$(mktemp -t keep.XXXXXX || true)"
    [[ -f "${keep}" ]] && cp -f "${keep}" "${tmp_keep}" || true

    shopt -s dotglob nullglob
    TO_DELETE=("${out_dir}"/*)
    PRUNED=()
    for p in "${TO_DELETE[@]:-}"; do
      [[ "$(basename "$p")" == ".gitkeep" ]] && continue
      PRUNED+=("$p")
    done
    if (( ${#PRUNED[@]} )); then
      if (( DRY )); then
        printf 'Would remove %d item(s) from %s:\n' "${#PRUNED[@]}" "${out_dir}"
        printf '  %s\n' "${PRUNED[@]}"
      else
        rm -rf -- "${PRUNED[@]}"
      fi
    fi
    # restore .gitkeep
    if [[ -f "${tmp_keep}" ]]; then mv -f "${tmp_keep}" "${keep}" || : ; else : > "${keep}"; fi
    (( DRY )) && echo "DRY RUN complete for ${out_dir}" || echo "Cleaned ${out_dir}"
  fi
}

# scan techniques at depth 2 and 3 (same as Makefile)
for d in "${ROOT}"/techniques/* "${ROOT}"/techniques/*/*; do
  [[ -d "$d" ]] || continue
  run_local_clean "$d"
done

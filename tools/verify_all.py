#!/usr/bin/env python3
# Author: Alfonso Pedro Ridao (s243942)
# 02232 Applied Cryptography - Fall 2025
import sys
import json, pathlib
import hashlib,argparse
import glob

# quick hash helper
def h(p: pathlib.Path, algo: str) -> str:
    return hashlib.new(algo, p.read_bytes()).hexdigest()

def verify_manifest(mpath: pathlib.Path):
    m=json.loads(mpath.read_text())
    base=mpath.parent
    arts = m.get("artifacts") or []
    if len(arts)<2:
        raise ValueError("manifest.artifacts must list at least two files")

    f1=(base / arts[0]).resolve()
    f2=(base / arts[1]).resolve()

    # calc hashes
    md5_equal= h(f1,"md5")==h(f2,"md5")
    sha256_diff = h(f1, "sha256")!=h(f2, "sha256")

    return {
        "technique": m.get("technique","?"),
        "language": m.get("language", "?"),
        "manifest": str(mpath),
        "f1": f1.name,
        "f2": f2.name,
        "md5_equal": md5_equal,
        "sha256_diff": sha256_diff,
    }


def main():
    ap=argparse.ArgumentParser(
        description="Verify MD5 collisions for one or more manifests and print a table."
    )
    ap.add_argument("manifests",nargs="+",
                    help="Path(s) or glob(s) to manifest.json files")
    ap.add_argument("--color",action="store_true",
                    help="Force ANSI colors on")
    ap.add_argument("--no-color", action="store_true",
                    help="Force ANSI colors off")
    args=ap.parse_args()

    # resolve globs
    manifest_paths=[]
    for pat in args.manifests:
        hits=glob.glob(pat,recursive=True)
        if hits:
            manifest_paths.extend(hits)
        else:
            manifest_paths.append(pat)  # let errors surface below

    # decide on color
    use_color=(args.color or sys.stdout.isatty()) and not args.no_color
    GREEN="\033[32m" if use_color else ""
    RED = "\033[31m" if use_color else ""
    BOLD="\033[1m" if use_color else ""
    DIM = "\033[2m" if use_color else ""
    RESET="\033[0m" if use_color else ""

    def paint_bool(val: bool,width: int)->str:
        raw=("True" if val else "False").ljust(width)
        return f"{GREEN}{raw}{RESET}" if val else f"{RED}{raw}{RESET}"

    results=[]
    for m in manifest_paths:
        mpath=pathlib.Path(m)
        try:
            res=verify_manifest(mpath)
            results.append(res)
        except Exception as e:
            # on error show row with fails
            results.append({
                "technique": "?",
                "language": "?",
                "manifest": str(mpath),
                "f1": "?",
                "f2": "?",
                "md5_equal": False,
                "sha256_diff": False,
                "_err": str(e),
            })

    if not results:
        print("No manifests found.",file=sys.stderr)
        return 2

    # dynamic column widths for neat alignment
    tech_w=max(9, max(len(r["technique"]) for r in results))
    lang_w = max(6,max(len(r["language"]) for r in results))
    md5_w,sha_w=6,9  # widths for True/False cells

    # header
    header=(
        f"{BOLD}{'Technique'.ljust(tech_w)}  "
        f"{'Lang'.ljust(lang_w)}  "
        f"{'MD5=='.ljust(md5_w)}  "
        f"{'SHA256!='.ljust(sha_w)}  "
        f"Manifest{RESET}"
    )
    underline=(
        f"{'-'*tech_w}  {'-'*lang_w}  {'-'*md5_w}  {'-'*sha_w}  {'-'*28}"
    )
    print()
    print(header)
    print(underline)

    # rows
    for r in results:
        md5_cell=paint_bool(r["md5_equal"],md5_w)
        sha_cell = paint_bool(r["sha256_diff"], sha_w)
        line=(
            f"{r['technique'].ljust(tech_w)}  "
            f"{r['language'].ljust(lang_w)}  "
            f"{md5_cell}  "
            f"{sha_cell}  "
            f"{r['manifest']}"
        )
        print(line)
        # if there was an error show a dim hint
        if "_err" in r:
            print(f"{DIM}   ↳ error: {r['_err']}{RESET}")

    print()
    return 0

if __name__=="__main__":
    sys.exit(main())

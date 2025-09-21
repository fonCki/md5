# md5 — Collision Lab Skeleton [Internal README]

Note: This README is for group members only and will be replaced before project submission.

Minimal, language-agnostic skeleton for our Applied Crypto project.

Each technique lives in its own folder and exposes a tiny CLI (run.sh). The top-level Makefile runs all techniques and a verifier.

---

## Why a manifest.json if filenames are constant?

We do standardize on constant artifact names (t1.bin, t2.bin) so the Makefile is simple. The manifest.json is still useful because it:
- records which technique/language produced the outputs (nice for logs and the report),
- allows future flexibility (if one experiment needs different names or extra artifacts, the verifier can read them from the manifest without changing Makefiles),
- gives humans a one-glance summary (notes, format used, etc.).

The verifier recomputes hashes from the files and ignores the manifest’s hash fields (so we do not “trust” self-reported values).

---

## Repo layout

```text
md5/
├─ README.md                 ← this file
├─ Makefile                  ← runs all techniques
├─ scripts/
│  ├─ run_all.sh             ← convenience wrapper (calls make all)
│  └─ clean.sh               ← deletes generated files in */out/
├─ tools/
│  ├─ verify_all.py          ← recomputes hashes and prints a table
│  └─ hashutil.py            ← tiny helper if you need hashing in Python
└─ techniques/
   ├─ identical-prefix/
   │  ├─ run.sh              ← entrypoint (language-agnostic)
   │  ├─ src/                ← your code (any language) goes here
   │  └─ out/                ← artifacts (t1.bin, t2.bin, manifest.json)
   ├─ chosen-prefix/
   │  ├─ run.sh
   │  ├─ src/
   │  └─ out/
   └─ reusable-format/
      ├─ run.sh
      ├─ src/
      └─ out/
```

---

## Requirements

- Linux or macOS with bash, make, python3 (3.8+).
- No global Node/C/Rust/etc. required (each technique can install/use what it needs inside src/).

Note (macOS): verify_all.py uses Python’s hashlib, so you do not need md5sum or sha256sum.

---

## CLI contract for each technique

Each techniques/<name>/run.sh must:

- accept: --out-dir <path>
- create in that folder:
  - t1.bin and t2.bin (the two outputs, same format for a given experiment)
  - manifest.json (see schema below)
- print manifest.json to stdout (good for logs)

### Minimal run.sh template

```bash
#!/usr/bin/env bash
set -euo pipefail

OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ -n "$OUT" ]] || { echo "missing --out-dir"; exit 2; }
mkdir -p "$OUT"

# Centralize artifact paths
T1="$OUT/t1.bin"
T2="$OUT/t2.bin"
MANIFEST="$OUT/manifest.json"

# 1) Produce the two artifacts (replace this stub with your real generator)
# Examples:
#   python3 src/main.py --out-a "$T1" --out-b "$T2"
#   node src/main.mjs --outA "$T1" --outB "$T2"
#   ./src/mytool --out-a "$T1" --out-b "$T2"

echo "stub-A" > "$T1"
echo "stub-B" > "$T2"

# 2) Write the manifest (hash fields are optional; verifier recomputes anyway)
cat > "$MANIFEST" <<JSON
{
  "technique": "identical-prefix",   // set per folder: identical-prefix | chosen-prefix | reusable
  "language": "free-choice",
  "artifacts": ["t1.bin","t2.bin"],
  "notes": "replace stub with real outputs"
}
JSON

# 3) Also print manifest to stdout (nice for logs)
cat "$MANIFEST"
```

Set "technique" to:
- identical-prefix in techniques/identical-prefix/run.sh
- chosen-prefix in techniques/chosen-prefix/run.sh
- reusable in techniques/reusable-format/run.sh

---

## Manifest schema

```json
{
  "technique": "identical-prefix | chosen-prefix | reusable",
  "language": "free-choice",
  "artifacts": ["t1.bin", "t2.bin"],
  "hashes": {
    "md5":    ["<optional>", "<optional>"],
    "sha256": ["<optional>", "<optional>"]
  },
  "notes": "short human note about the demo (format used, constraints, etc.)"
}
```

The verifier doesn’t trust these hash values; it recomputes from files.

---

## Run a single technique

```bash
# Identical-prefix only
techniques/identical-prefix/run.sh --out-dir techniques/identical-prefix/out

# Chosen-prefix only
techniques/chosen-prefix/run.sh --out-dir techniques/chosen-prefix/out

# Reusable-format only
techniques/reusable-format/run.sh --out-dir techniques/reusable-format/out
```

This creates or overwrites t1.bin, t2.bin, manifest.json in the out/ directory.

---

## Run everything

```bash
make all
# or
scripts/run_all.sh
```

The Makefile calls all three run.sh scripts in order.

---

## Verify results

```bash
make verify
# or
python3 tools/verify_all.py techniques/*/out/manifest.json
```

You’ll see a table like:

```text
Technique         Lang          MD5==   SHA256!=   Manifest
---------------   ------        ------  ---------  ----------------------------
identical-prefix  free-choice   True    True       techniques/identical-prefix/out/manifest.json
chosen-prefix     free-choice   True    True       techniques/chosen-prefix/out/manifest.json
reusable          free-choice   True    True       techniques/reusable-format/out/manifest.json
```

Success = MD5== True and SHA256!= True.
If MD5== is False → you don’t have a collision yet.
If SHA256!= is False → the two files are probably identical bytes (not interesting).

---

## Clean up

```bash
make clean
```

Deletes everything under */out/ except .gitkeep.

---

## Tips

- Keep generator code in src/ and call it from run.sh (language is free choice).
- Don’t edit files under out/ by hand. Always regenerate via run.sh.
- Keep both outputs in the same format for each experiment (two PNGs, two PDFs, etc.) so real apps can open them and you can argue the security impact clearly.

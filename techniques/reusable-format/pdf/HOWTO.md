# HOWTO — PDF reusable MD5 collision (manual run)

This HOWTO mirrors the automated script: running these commands manually is **equivalent** to running:
`techniques/reusable-format/pdf/run.sh --out-dir techniques/reusable-format/pdf/out`.
Use this HOWTO if you want to see/execute each step yourself; the script simply automates the same steps.

Run from the **repo root**.

- **Ubuntu 24.04.2 LTS (grader):** `python3` is present by default. If `mutool` or `pdftotext` are missing, install with:
  - `sudo apt-get update && sudo apt-get install -y mupdf-tools poppler-utils`
- **macOS (dev):** `brew install mupdf poppler`. The commands below auto-fallback for hashes (`md5` / `shasum -a 256`) if GNU tools are absent.

## 1) Clean output
```bash
TECH="techniques/reusable-format/pdf"
OUT="$TECH/out"

"$TECH/clean.sh"
: > "$OUT/verification.txt"
```

## 2) Stage inputs and normalize (deterministic layout)
```bash
WORKDIR="$(mktemp -d)"

# Your two PDFs
cp "$TECH/src/assets/inputs/brownies_recipe.pdf"              "$WORKDIR/A.pdf"
cp "$TECH/src/assets/inputs/brownies_recipe_with_poison.pdf"  "$WORKDIR/B.pdf"

# Normalize both with MuPDF (stable object/xref layout)
mutool clean -gg "$WORKDIR/A.pdf" "$WORKDIR/A.norm.pdf"
mutool clean -gg "$WORKDIR/B.pdf" "$WORKDIR/B.norm.pdf"
```

## 3) Run the bundled generator (offline; no dummy.pdf required)
```bash
# Stage generator and required payload blocks into the workdir
cp "$TECH/src/pdf.py"                   "$WORKDIR/pdf.py"
cp "$TECH/src/assets/payloads/pdf1.bin" "$WORKDIR/pdf1.bin"
cp "$TECH/src/assets/payloads/pdf2.bin" "$WORKDIR/pdf2.bin"

# Generate colliding PDFs (two-arg mode)
( cd "$WORKDIR" && python3 ./pdf.py A.norm.pdf B.norm.pdf )

# Copy results into the technique's out/ (handles coll-1/2 or collision1/2 names)
cp "$WORKDIR"/coll*1*.pdf "$OUT/collision1.pdf" 2>/dev/null || cp "$WORKDIR/collision1.pdf" "$OUT/collision1.pdf"
cp "$WORKDIR"/coll*2*.pdf "$OUT/collision2.pdf" 2>/dev/null || cp "$WORKDIR/collision2.pdf" "$OUT/collision2.pdf"
```

## 4) Verify hashes (cross-platform) + compact semantic check
```bash
# MD5 equality + SHA-256 difference
md5sum    "$OUT/collision1.pdf" "$OUT/collision2.pdf" | tee -a "$OUT/verification.txt"  || md5    "$OUT/collision1.pdf" "$OUT/collision2.pdf" | tee -a "$OUT/verification.txt"
sha256sum "$OUT/collision1.pdf" "$OUT/collision2.pdf" | tee -a "$OUT/verification.txt"  || shasum -a 256 "$OUT/collision1.pdf" "$OUT/collision2.pdf" | tee -a "$OUT/verification.txt"

# Streamed semantic check: compare SHA-256 of extracted text (no temp files)
printf "\n== TEXT HASH CHECK (pdftotext | SHA256 of text) ==\n" | tee -a "$OUT/verification.txt"
( pdftotext "$OUT/collision1.pdf" - | sha256sum || pdftotext "$OUT/collision1.pdf" - | shasum -a 256 ) | tee -a "$OUT/verification.txt"
( pdftotext "$OUT/collision2.pdf" - | sha256sum || pdftotext "$OUT/collision2.pdf" - | shasum -a 256 ) | tee -a "$OUT/verification.txt"

# Optional tiny snippets for human eyeballs (first 160 chars)
printf "\n== SHORT TEXT SNIPPETS (first 160 chars) ==\n" | tee -a "$OUT/verification.txt"
echo -n "c1: " | tee -a "$OUT/verification.txt"; pdftotext "$OUT/collision1.pdf" - | head -c 160 | tr '\n' ' ' | tee -a "$OUT/verification.txt"; echo | tee -a "$OUT/verification.txt"
echo -n "c2: " | tee -a "$OUT/verification.txt"; pdftotext "$OUT/collision2.pdf" - | head -c 160 | tr '\n' ' ' | tee -a "$OUT/verification.txt"; echo | tee -a "$OUT/verification.txt"
```

## 5) Write the manifest (the verifier reads artifact names from here)
```bash
cat > "$OUT/manifest.json" <<'JSON'
{
  "technique": "reusable",
  "language": "bash+python-stdlib",
  "artifacts": ["collision1.pdf", "collision2.pdf"],
  "notes": "PDF reusable-collision: MD5 equal, SHA-256 different; opens in common viewers; pdftotext text-hashes differ."
}
JSON
```

## 6) Optional: project table
```bash
python3 tools/verify_all.py "$OUT/manifest.json"
```

## 7) Cleanup temp work dir
```bash
rm -rf "$WORKDIR"
```

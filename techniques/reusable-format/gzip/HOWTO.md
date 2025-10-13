# HOWTO — GZIP (.tar.gz) reusable MD5 collision (manual run)

This HOWTO mirrors the automated script: running these commands manually is **equivalent** to running:
`techniques/reusable-format/gzip/run.sh --out-dir techniques/reusable-format/gzip/out`.
Use this HOWTO if you want to see/execute each step yourself; the script simply automates the same steps.

Run from the **repo root**. Assumes Ubuntu 24.04.2 LTS with `python3`, `tar`, `gzip`, `md5sum`, `sha256sum`, `diff`.

## 1) Clean output
```bash
TECH="techniques/reusable-format/gzip"
OUT="$TECH/out"

"$TECH/clean.sh"

: > "$OUT/verification.txt"
```

## 2) Build the two payload tarballs, then gzip deterministically
```bash
WORKDIR="$(mktemp -d)"
tar -C "$TECH/src/assets/benign"    -cf "$WORKDIR/A.tar" treeA
tar -C "$TECH/src/assets/malicious" -cf "$WORKDIR/B.tar" treeB
GZIP=-n gzip -9 "$WORKDIR/A.tar"
GZIP=-n gzip -9 "$WORKDIR/B.tar"
```

## 3) Run the bundled generator (offline)
```bash
cp "$TECH/src/gz.py"                         "$WORKDIR/gz.py"
cp "$TECH/src/assets/prefixes/prefix1.gz"    "$WORKDIR/prefix1.gz"
cp "$TECH/src/assets/prefixes/prefix2.gz"    "$WORKDIR/prefix2.gz"

( cd "$WORKDIR" && python3 ./gz.py A.tar.gz B.tar.gz )   # prints "Success!" + MD5

# Copy results into the technique's out/
cp "$WORKDIR/coll-1.gz" "$OUT/collision1.tar.gz"
cp "$WORKDIR/coll-2.gz" "$OUT/collision2.tar.gz"
```

## 4) Verify hashes and integrity
```bash
md5sum    "$OUT/collision1.tar.gz" "$OUT/collision2.tar.gz" | tee -a "$OUT/verification.txt"
sha256sum "$OUT/collision1.tar.gz" "$OUT/collision2.tar.gz" | tee -a "$OUT/verification.txt"

gzip -t "$OUT/collision1.tar.gz" && echo "collision1: OK" | tee -a "$OUT/verification.txt"
gzip -t "$OUT/collision2.tar.gz" && echo "collision2: OK" | tee -a "$OUT/verification.txt"
```

## 5) Extract and show differences
```bash
mkdir -p "$OUT/extract1" "$OUT/extract2"
tar -xzf "$OUT/collision1.tar.gz" -C "$OUT/extract1"
tar -xzf "$OUT/collision2.tar.gz" -C "$OUT/extract2"

echo "== DIFF (extract1 vs extract2) ==" | tee -a "$OUT/verification.txt"
diff -r "$OUT/extract1" "$OUT/extract2" | tee -a "$OUT/verification.txt" || true
```

## 6) Write the manifest (the verifier reads artifact names from here)
```bash
cat > "$OUT/manifest.json" <<'JSON'
{
  "technique": "reusable",
  "language": "bash+python-stdlib",
  "artifacts": ["collision1.tar.gz", "collision2.tar.gz"],
  "notes": "GZIP (.tar.gz) reusable-collision: MD5 equal, SHA-256 different, gzip -t OK, extracted trees differ."
}
JSON
```

## 7) Optional: project table
```bash
python3 tools/verify_all.py "$OUT/manifest.json"
```

## 8) Cleanup temp work dir
```bash
rm -rf "$WORKDIR"
```


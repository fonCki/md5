# HOWTO — JPEG reusable MD5 collision (manual run)

This HOWTO mirrors the automated script: running these commands manually is **equivalent** to running:
`techniques/reusable-format/jpeg/run.sh --out-dir techniques/reusable-format/jpeg/out`.
Use this HOWTO if you want to see/execute each step yourself; the script simply automates the same steps.

Run from the **repo root**.

- **Ubuntu 24.04.2 LTS (grader):** `python3` and GNU `md5sum`/`sha256sum` are present by default. If `jpegtran` is missing, the script will try to install `libjpeg-turbo-progs` automatically (using `sudo apt-get -y`).  
- **macOS (dev):** If `jpegtran` is missing, install via Homebrew: `brew install jpeg` (or `jpeg-turbo`). The script uses hash fallbacks (`md5` / `shasum -a 256`) so you do **not** need coreutils.

## 1) Clean output
```bash
TECH="techniques/reusable-format/jpeg"
OUT="$TECH/out"

"$TECH/clean.sh"
: > "$OUT/verification.txt"
```

## 2) Stage inputs and preprocess (progressive JPEGs)
```bash
WORKDIR="$(mktemp -d)"

# Use your two photos
cp "$TECH/src/assets/inputs/messi.jpg"   "$WORKDIR/a.jpg"
cp "$TECH/src/assets/inputs/ronaldo.jpg" "$WORKDIR/b.jpg"

# Convert to progressive (stable layout for the trick)
jpegtran -copy all -optimize -progressive "$WORKDIR/a.jpg" > "$WORKDIR/a_prog.jpg"
jpegtran -copy all -optimize -progressive "$WORKDIR/b.jpg" > "$WORKDIR/b_prog.jpg"
```

> If `jpegtran` is missing, on Ubuntu: `sudo apt-get update && sudo apt-get install -y libjpeg-turbo-progs`. On macOS: `brew install jpeg`.

## 3) Run the bundled generator (offline)
```bash
# Stage generator and required payload blocks into the workdir
cp "$TECH/src/jpg.py"                          "$WORKDIR/jpg.py"
cp "$TECH/src/assets/payloads/jpg1.bin"        "$WORKDIR/jpg1.bin"
cp "$TECH/src/assets/payloads/jpg2.bin"        "$WORKDIR/jpg2.bin"

# Generate colliding JPEGs (outputs named coll-1/2.jpg or collision1/2.jpg)
( cd "$WORKDIR" && python3 ./jpg.py a_prog.jpg b_prog.jpg )

# Copy results into the technique's out/ (wildcards handle both naming styles)
cp "$WORKDIR"/coll*1*.jpg "$OUT/collision1.jpg"
cp "$WORKDIR"/coll*2*.jpg "$OUT/collision2.jpg"
```

## 4) Verify hashes (cross-platform)
```bash
# Ubuntu (GNU coreutils present):
md5sum    "$OUT/collision1.jpg" "$OUT/collision2.jpg" | tee -a "$OUT/verification.txt"
sha256sum "$OUT/collision1.jpg" "$OUT/collision2.jpg" | tee -a "$OUT/verification.txt"

# macOS alternative if needed:
# md5 "$OUT/collision1.jpg" "$OUT/collision2.jpg" | tee -a "$OUT/verification.txt"
# shasum -a 256 "$OUT/collision1.jpg" "$OUT/collision2.jpg" | tee -a "$OUT/verification.txt"
```

## 5) Write the manifest (the verifier reads artifact names from here)
```bash
cat > "$OUT/manifest.json" <<'JSON'
{
  "technique": "reusable",
  "language": "bash+python-stdlib",
  "artifacts": ["collision1.jpg", "collision2.jpg"],
  "notes": "JPEG reusable-collision from two user photos (with prebuilt payload blocks): MD5 equal, SHA-256 different; both images open normally and show different visuals."
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

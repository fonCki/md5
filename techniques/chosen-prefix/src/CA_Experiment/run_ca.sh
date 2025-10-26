#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
OUT_DIR="out_ca"
PREFIX_LEN_A=21   # length of "PrefixA: Demo benign\n"
PREFIX_LEN_B=24   # length of "PrefixB: Demo malicious\n"
RESERVED_PAYLOAD_WARNING=16384

# use virtual env for python dependencies
if [ ! -d venv ]; then
  python3 -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt
else
  source venv/bin/activate
fi

mkdir -p "$OUT_DIR"

echo "[1] Generating TBSCertificate templates..."
python3 build_tbs_templates.py
mv tbs_prefixA.der tbs_prefixB.der "$OUT_DIR"

echo "[2] Copy prefixes for CPC pipeline..."
# Split the TBS files into chosen-prefix inputs. We split BEFORE the payload.
# The custom extension payload begins at byte  ?  we detect automatically here:
PY_SPLIT=$(cat << 'EOF'
import sys
oid = bytes([0x06,0x07,0x2A,0x03,0x04,0x05,0x06,0x07,0x08])
for name in ["tbs_prefixA.der","tbs_prefixB.der"]:
    buf=open(name,"rb").read()
    i=buf.find(oid)
    if i<0: raise SystemExit("OID not found")
    # extn_value payload starts 13 bytes later (OID+critical+len fields)
    split=i+13
    print(f"{name} SPLIT_AT={split}")
EOF
)
pushd "$OUT_DIR" >/dev/null
python3 - <<EOF
$PY_SPLIT
EOF

# Use detected split position
SPLIT=$(python3 - << 'EOF'
oid = bytes([0x06,0x07,0x2A,0x03,0x04,0x05,0x06,0x07,0x08])
buf=open("tbs_prefixA.der","rb").read()
i=buf.find(oid)
if i<0: raise SystemExit("OID not found")
print(i+13)
EOF
)

dd if=tbs_prefixA.der of=prefixA.bin bs=1 count="$SPLIT"
dd if=tbs_prefixB.der of=prefixB.bin bs=1 count="$SPLIT"
dd if=tbs_prefixA.der of=common_tail.bin bs=1 skip="$SPLIT"

echo "[3] Running chosen-prefix collision pipeline..."
cp out_ca/prefixA.bin out_ca/cpc/prefixA.bin
cp out_ca/prefixB.bin out_ca/cpc/prefixB.bin
cp out_ca/common_tail.bin out_ca/cpc/common_tail.bin

../../../run.sh --out-dir "$OUT_DIR/cpc" || { echo "CPC failed"; exit 1; }
cp "$OUT_DIR/cpc/SA.bin" "$OUT_DIR"
cp "$OUT_DIR/cpc/SB.bin" "$OUT_DIR"

echo "[4] Overlaying linking blocks into DER payload..."
python3 ../overlay_cpc_into_tbs.py \
  tbs_prefixA.der $PREFIX_LEN_A SA.bin "$OUT_DIR/tbsA_final.der"
python3 ../overlay_cpc_into_tbs.py \
  tbs_prefixB.der $PREFIX_LEN_B SB.bin "$OUT_DIR/tbsB_final.der"

echo "[5] Signing both TBS files using MD5..."
python3 ../sign_md5_rsa.py "$OUT_DIR/tbsA_final.der" "$OUT_DIR/sigA.bin"
python3 ../sign_md5_rsa.py "$OUT_DIR/tbsB_final.der" "$OUT_DIR/sigB.bin"

echo "[6] Verifying signature transfer..."
python3 ../verify_md5_rsa.py "$OUT_DIR/tbsA_final.der" "$OUT_DIR/sigA.bin"
python3 ../verify_md5_rsa.py "$OUT_DIR/tbsB_final.der" "$OUT_DIR/sigA.bin"  # same signature!

echo "DONE — Chosen-prefix CA demo completed."
echo "Files are in: $OUT_DIR"
popd >/dev/null

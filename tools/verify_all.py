#!/usr/bin/env python3
import sys, json, pathlib, hashlib

def h(p, algo): return hashlib.new(algo, pathlib.Path(p).read_bytes()).hexdigest()

def verify_manifest(mpath):
    m = json.loads(pathlib.Path(mpath).read_text())
    base = pathlib.Path(mpath).parent
    f1, f2 = (base / m["artifacts"][0], base / m["artifacts"][1])
    return {
        "technique": m.get("technique","?"),
        "language": m.get("language","?"),
        "f1": str(f1.name),
        "md5_equal": h(f1,"md5")==h(f2,"md5"),
        "sha256_diff": h(f1,"sha256")!=h(f2,"sha256")
    }

if __name__=="__main__":
    if len(sys.argv)<2:
        print("usage: verify_all.py <manifest.json> [more ...]"); sys.exit(2)
    print("\nTechnique         Lang    MD5==   SHA256!=   Manifest")
    print("---------------  ------  ------  ---------  ----------------------------")
    for m in sys.argv[1:]:
        try:
            r = verify_manifest(m)
            print(f"{r['technique']:<15}  {r['language']:<6}  {str(r['md5_equal']):<6}  {str(r['sha256_diff']):<9}  {m}")
        except Exception:
            print(f"{'?':<15}  {'?':<6}  {'False':<6}  {'False':<9}  {m}")

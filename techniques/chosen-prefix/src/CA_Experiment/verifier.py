from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import load_pem_public_key

pub = load_pem_public_key(open('demo_pub.pem','rb').read())

def verify(tbs_path, sig_path):
    tbs = open(tbs_path,'rb').read()
    sig = open(sig_path,'rb').read()
    try:
        pub.verify(sig, tbs, padding.PKCS1v15(), hashes.MD5())
        print(f"VERIFIED: {tbs_path}")
    except Exception as e:
        print(f"FAILED: {tbs_path} -> {e}")

if __name__ == "__main__":
    verify('tbsA_prefixA.der','sigA.bin')
    verify('tbsB_prefixB.der','sigB.bin')
    verify('tbsA_final.der','sigA.bin')
    verify('tbsB_final.der','sigB.bin')

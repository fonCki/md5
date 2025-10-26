from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa, utils, serialization
from cryptography.hazmat.backends import default_backend
import sys

from cryptography.hazmat.primitives.serialization import load_pem_private_key

priv = load_pem_private_key(open('demo_key.pem','rb').read(), password=None, backend=default_backend())

def sign_tbs(tbs_path, out_sig):
    tbs = open(tbs_path,'rb').read()
    # compute MD5 digest and sign via PKCS1v1.5 with MD5
    signature = priv.sign(
        tbs,
        padding.PKCS1v15(),
        hashes.MD5() # use MD5 as the hash function!!!
    )
    open(out_sig,'wb').write(signature)

if __name__ == "__main__":
    sign_tbs('tbsA_final.der','sigA.bin')
    sign_tbs('tbsB_final.der','sigB.bin')
    print("Signed")

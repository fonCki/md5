from asn1crypto import x509, core, algos, keys
from cryptography.hazmat.primitives import serialization
import os

def load_spki_from_pem(pem_path):
    pem_bytes = open(pem_path, "rb").read()
    pub = serialization.load_pem_public_key(pem_bytes)
    spki_der = pub.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo
    )
    return keys.PublicKeyInfo.load(spki_der)

def make_tbs_with_prefix(prefix_bytes, out_path, pub_pem_path="demo_pub.pem"):
    version = x509.Version('v3')
    serial = core.Integer(1)
    sig_alg = algos.SignedDigestAlgorithm({'algorithm': 'sha256_rsa'})
    issuer = x509.Name.build({'common_name': 'Demo Issuer'})
    spki    = load_spki_from_pem(pub_pem_path)

    subj = x509.Name.build({'common_name': 'Demo Subject'})

    # Construct a custom extension with a fixed-length OCTET STRING (to hold our prefix + padding) payload.
    # Reserve a fixed-length value (e.g., 512 bytes).
    # I'll place the collision prefix at the start.
    reserved_length = 16384  # Usually large enough for chosen-prefix collisions
    payload = bytearray(reserved_length) # initialized to zeros
    payload[0:len(prefix_bytes)] = prefix_bytes # insert the prefix at the start of the payload

    ext = x509.Extension({
        'extn_id': '1.2.3.4.5.6.7.8',  # made-up OID. Should work fiiiiine
        'critical': False, # usually false for custom extentions, as it's not understood by default
        'extn_value': core.ParsableOctetString(bytes(payload)) # the reserved fixed-length payload
    })

    exts = x509.Extensions([ext])

    # Make a very small TBSCertificate manually (minimal fields)
    tbs = x509.TbsCertificate({
        'version': version,
        'serial_number': serial,
        'signature': sig_alg,
        'issuer': issuer,
        'validity': {
            'not_before': core.GeneralizedTime('20250101000000Z'),  # Jan 1, 2025 onwards
            'not_after': core.GeneralizedTime('20260101000000Z'),  # 1 year validity
        },
        'subject': subj,
        'subject_public_key_info': spki,
        'extensions': exts
    })
    with open(out_path, 'wb') as f:
        f.write(tbs.dump())

if __name__ == "__main__":
    make_tbs_with_prefix(b'PrefixA: Demo benign\n', 'tbs_prefixA.der')
    make_tbs_with_prefix(b'PrefixB: Demo malicious\n', 'tbs_prefixB.der')

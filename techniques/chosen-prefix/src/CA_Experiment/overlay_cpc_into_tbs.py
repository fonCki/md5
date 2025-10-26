# overlay_cpc_into_tbs.py
import sys, binascii

OID = bytes([0x06,0x07,0x2A,0x03,0x04,0x05,0x06,0x07,0x08])  # 1.2.3.4.5.6.7.8

def find_payload(buf):
    i = buf.find(OID)
    if i < 0:
        raise RuntimeError("OID 1.2.3.4.5.6.7.8 not found")
    j = i + len(OID)
    if buf[j] != 0x04:  # OCTET STRING tag
        raise RuntimeError("Expected OCTET STRING after OID")
    # handle short/long length
    l1 = buf[j+1]
    if l1 & 0x80:
        n = l1 & 0x7F
        if n == 2:
            L = buf[j+2]*256 + buf[j+3]
            payload_start = j + 4
        else:
            raise RuntimeError("Unexpected length form")
    else:
        L = l1
        payload_start = j + 2
    return payload_start, L

def overlay(tbs_path, prefix_len, s_path, out_path):
    tbs = bytearray(open(tbs_path, 'rb').read())
    S  = open(s_path, 'rb').read()
    payload_start, payload_len = find_payload(tbs)
    max_len = payload_len - prefix_len
    if len(S) > max_len:
        raise RuntimeError(f"Linking block too large: {len(S)} > {max_len} (increase reserved_length)")
    # overlay S starting right after the textual prefix
    off = payload_start + prefix_len
    tbs[off:off+len(S)] = S
    # leave the remainder of the payload (zeros) as-is
    open(out_path, 'wb').write(tbs)
    print(f"Wrote {out_path} (payload_start={payload_start}, payload_len={payload_len}, S={len(S)} bytes)")

if __name__ == "__main__":
    # Example usage:
    #   python overlay_cpc_into_tbs.py
    # After you generate SA.bin/SB.bin and you know your textual prefix lengths:
    overlay('tbs_prefixA.der', prefix_len=21, s_path='SA.bin', out_path='tbsA_final.der')
    overlay('tbs_prefixB.der', prefix_len=24, s_path='SB.bin', out_path='tbsB_final.der')

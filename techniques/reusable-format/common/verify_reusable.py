#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
reusable collision analyzer - jpeg/pdf/gzip

checks:
- md5 collision + sha256 diff
- first diff byte, suffix boundaries
- format specifics (COM markers for jpg, %%EOF for pdf, gzip headers)
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path
from typing import Optional,Tuple,List,Dict


# helpers
def md5sum(b: bytes) -> str:
    return hashlib.md5(b).hexdigest()

def sha256sum(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def hexdump_head(data: bytes, n: int=96) -> str:
    out=[]
    for off in range(0,min(len(data),n),16):
        chunk=data[off:off+16]
        hexs=" ".join(f"{bb:02x}" for bb in chunk)
        asc="".join(chr(bb) if 32<=bb<127 else "." for bb in chunk)
        out.append(f"{off:08x}  {hexs:<47}  |{asc}|")
    return "\n".join(out)


def first_diff(a: bytes,b: bytes) -> Optional[Tuple[int,int,int]]:
    n=min(len(a),len(b))
    for i in range(n):
        if a[i]!=b[i]:
            return i,a[i],b[i]
    return None if len(a)==len(b) else (n,-1,-1)


def all_diffs_upto(a: bytes,b: bytes,limit_inclusive: int) -> List[Tuple[int,int,int]]:
    out=[]
    n=min(len(a),len(b),limit_inclusive+1)
    for i in range(n):
        if a[i]!=b[i]:
            out.append((i,a[i],b[i]))
    return out


def common_suffix_start(a: bytes,b: bytes) -> int:
    # find where identical tail begins
    i=1
    m=min(len(a),len(b))
    while i<=m and a[-i]==b[-i]:
        i+=1
    i-=1
    return len(a)-i


def have(cmd: str) -> bool:
    return shutil.which(cmd) is not None


# jpeg parsing
def jpeg_find_second_com(data: bytes) -> Optional[Tuple[int,int,int,int]]:
    """
    returns (marker_pos, len_pos, length, next_from_marker) for 2nd COM segment
    marker = FF FE
    """
    if not(len(data)>=4 and data[0:2]==b"\xFF\xD8"):
        return None
    i=2
    com_seen=0
    while i+3<=len(data):
        # scan for 0xFF
        if data[i]!=0xFF:
            i+=1
            continue
        j=i
        while j<len(data) and data[j]==0xFF:
            j+=1
        if j>=len(data):
            break
        marker=data[j]
        i=j+1
        # standalone markers (no len field)
        if marker in (0xD8,0xD9,0x01) or (0xD0<=marker<=0xD7):
            continue
        if i+1>=len(data):
            break
        L=(data[i]<<8)|data[i+1]  # big endian
        if marker==0xFE:  # COM marker
            com_seen+=1
            if com_seen==2:
                marker_pos=j-1  # points to 0xFF
                next_from_marker=marker_pos+L
                return marker_pos,i,L,next_from_marker
        i+=L
    return None


# pdf parsing
def pdf_find_eofs(data: bytes) -> Tuple[int,int,int]:
    """
    returns (first_eof, last_eof, trailing_bytes)
    eof token is '%%EOF'
    """
    tok=b"%%EOF"
    first=data.find(tok)
    last=data.rfind(tok)
    trailing=-1
    if last!=-1:
        trailing=len(data)-(last+len(tok))
    return first,last,trailing


# gzip parsing
def gzip_parse_header(b: bytes) -> Tuple[int,Dict]:
    # returns (header_len, info_dict)
    if not(len(b)>=10 and b[0:2]==b"\x1f\x8b"):
        return 0,{"valid":False}
    cm,flg=b[2],b[3]
    mtime=struct.unpack("<I",b[4:8])[0]
    xfl,os_=b[8],b[9]
    i=10
    info={"valid":True,"cm":cm,"flg":flg,"mtime":mtime,"xfl":xfl,"os":os_,
          "fname":None,"comment":None,"xlen":None}
    if flg&0x04:  # FEXTRA
        xlen=struct.unpack("<H",b[i:i+2])[0]
        i+=2
        info["xlen"]=xlen
        i+=xlen
    if flg&0x08:  # FNAME
        j=b.find(b"\x00",i)
        info["fname"]=b[i:j].decode("latin-1","replace")
        i=j+1
    if flg&0x10:  # FCOMMENT
        j=b.find(b"\x00",i)
        info["comment"]=b[i:j].decode("latin-1","replace")
        i=j+1
    if flg&0x02:  # FHCRC
        i+=2
    return i,info


def gzip_decompress_all(b: bytes) -> bytes:
    # decompress all gzip members
    out=bytearray()
    bio=io.BytesIO(b)
    while True:
        pos=bio.tell()
        try:
            with gzip.GzipFile(fileobj=bio) as gz:
                out.extend(gz.read())
            if bio.tell()==pos:  # no progress
                break
            if bio.tell()>=len(b):
                break
        except OSError:
            break
    return bytes(out)


# resolve output filenames from manifest or defaults
def resolve_outputs(out_dir: Path,fmt: str) -> Tuple[Path,Path,str]:
    """
    try manifest.json first (artifacts list), fallback to defaults
    for gzip also handles .tar.gz via globbing
    returns (path1, path2, ext_string)
    """
    # try manifest
    man=out_dir/"manifest.json"
    if man.exists():
        try:
            data=json.loads(man.read_text())
            arts=data.get("artifacts",[])
            if len(arts)>=2:
                p1=out_dir/arts[0]
                p2=out_dir/arts[1]
                # TODO: mejorar deteccion de extension compuesta
                def suffix_str(p: Path) -> str:
                    return "".join(p.suffixes) or p.suffix
                ext_print=suffix_str(p1) if suffix_str(p1) else {
                    "jpeg":".jpg","pdf":".pdf","gzip":".gz"
                }[fmt]
                return p1,p2,ext_print.lstrip(".")
        except Exception:
            pass

    # fallbacks
    if fmt=="jpeg":
        return out_dir/"collision1.jpg",out_dir/"collision2.jpg","jpg"
    if fmt=="pdf":
        return out_dir/"collision1.pdf",out_dir/"collision2.pdf","pdf"
    if fmt=="gzip":
        # look for most specific gz names (prefers .tar.gz)
        cand1=sorted(out_dir.glob("collision1.*gz"),
                     key=lambda p: len("".join(p.suffixes)),reverse=True)
        cand2=sorted(out_dir.glob("collision2.*gz"),
                     key=lambda p: len("".join(p.suffixes)),reverse=True)
        if cand1 and cand2:
            return cand1[0],cand2[0],"gz"
        return out_dir/"collision1.gz",out_dir/"collision2.gz","gz"

    raise SystemExit(f"unsupported format: {fmt}")


# main analysis
def analyze(fmt: str,out_dir: Path,inputs_dir: Optional[Path],emit_tools: bool) -> None:
    out_dir=out_dir.resolve()

    # select outputs
    c1_path,c2_path,ext_print=resolve_outputs(out_dir,fmt)
    if not c1_path.exists() or not c2_path.exists():
        raise SystemExit(f"missing outputs in {out_dir} (need {c1_path.name} & {c2_path.name})")

    c1=c1_path.read_bytes()
    c2=c2_path.read_bytes()

    # calc hashes
    md5_1,md5_2=md5sum(c1),md5sum(c2)
    sha_1,sha_2=sha256sum(c1),sha256sum(c2)
    s1,s2=len(c1),len(c2)
    fd=first_diff(c1,c2)
    if not fd:
        raise SystemExit("files are identical - no collision")
    off0,b1,b2=fd
    suffix_start=common_suffix_start(c1,c2)
    suffix_len=len(c1)-suffix_start

    # dump first 96 bytes
    (out_dir/"c1.head.hex").write_text(hexdump_head(c1,96))
    (out_dir/"c2.head.hex").write_text(hexdump_head(c2,96))

    # format specific analysis
    fmt_lines: List[str]=[]
    if fmt=="jpeg":
        # nota: recordar que los diffs estan en 0..73 para jpeg
        diffs_prefix=all_diffs_upto(c1,c2,73)
        fmt_lines.append("## First difference & collision prefix")
        fmt_lines.append("```")
        fmt_lines.append(f"first diff @ byte {off0} (0x{off0:X}) : {b1:02X} -> {b2:02X}")
        fmt_lines.append("diffs inside 0..73:")
        for i,x,y in diffs_prefix:
            fmt_lines.append(f"  byte {i:3d} : {x:02X} -> {y:02X}")
        fmt_lines.append("```")
        # find 2nd COM marker
        com2=jpeg_find_second_com(c1)
        if com2:
            marker_pos,len_pos,L,next_from_marker=com2
            L2=((c2[len_pos]<<8)|c2[len_pos+1])
            next2=(marker_pos+L2)
            fmt_lines+=[
                "## Steering flip (2nd COM length)",
                "```",
                f"COM@{marker_pos} length: c1 = {L} (0x{L:04X})   c2 = {L2} (0x{L2:04X})",
                f"next-marker offsets from COM start ({marker_pos}): c1 -> {next_from_marker}   c2 -> {next2}",
                "```",
            ]

    elif fmt=="pdf":
        first_eof,last_eof,trailing=pdf_find_eofs(c1)
        first_eof2,last_eof2,trailing2=pdf_find_eofs(c2)
        fmt_lines+=[
            "## PDF markers",
            "```",
            f"first %%EOF offsets:   c1={first_eof}   c2={first_eof2}",
            f"last  %%EOF offsets:   c1={last_eof}    c2={last_eof2}",
            f"trailing bytes after last %%EOF: c1={trailing}   c2={trailing2}",
            "```",
        ]

    elif fmt=="gzip":
        h1_off,h1=gzip_parse_header(c1)
        h2_off,h2=gzip_parse_header(c2)
        fmt_lines+=[
            "## GZIP headers",
            "```",
            f"header lengths: c1={h1_off}   c2={h2_off}",
            f"flags (c1/c2):  0x{h1.get('flg',0):02X} / 0x{h2.get('flg',0):02X}",
            f"FNAME (c1/c2):  {h1.get('fname')} / {h2.get('fname')}",
            "```",
        ]
        # decompress and hash payloads
        try:
            d1=gzip_decompress_all(c1)
            d2=gzip_decompress_all(c2)
            fmt_lines+=[
                "## Decompressed payloads",
                "```",
                f"len(c1)= {len(d1)}  sha256= {sha256sum(d1)}",
                f"len(c2)= {len(d2)}  sha256= {sha256sum(d2)}",
                "```",
            ]
        except Exception as e:
            fmt_lines+=[f"(decompression failed: {e})"]

    # build analysis.md
    lines: List[str]=[]
    lines.append(f"# Reusable {fmt.upper()} MD5-collision — Analysis\n")
    lines.append("## Files\n")
    lines.append(f"- {c1_path.name} size **{s1}** bytes")
    lines.append(f"- {c2_path.name} size **{s2}** bytes\n")
    lines.append("## Hashes\n```")
    lines.append(f"MD5(c1)    {md5_1}")
    lines.append(f"MD5(c2)    {md5_2}\n")
    lines.append(f"SHA256(c1) {sha_1}")
    lines.append(f"SHA256(c2) {sha_2}")
    lines.append("```\n")
    lines.append("## Identical suffix\n```")
    lines.append(f"suffix starts at byte {suffix_start} (0x{suffix_start:X})")
    lines.append(f"identical tail length = {suffix_len} bytes")
    lines.append("```\n")
    lines+=fmt_lines
    (out_dir/"analysis.md").write_text("\n".join(lines))

    # print summary
    print(f"[{fmt}] MD5: {md5_1} == {md5_2} | SHA256 differ | size {s1}=={s2} | suffix@{suffix_start} len={suffix_len}")
    print(f"Wrote: {out_dir/'analysis.md'}, {out_dir/'c1.head.hex'}, {out_dir/'c2.head.hex'}")


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--format",choices=["jpeg","pdf","gzip"],required=True)
    p.add_argument("--out-dir",required=True)
    p.add_argument("--inputs-dir")   # reserved for jpeg provenance
    p.add_argument("--with-tools",action="store_true")  # reserved
    a=p.parse_args()
    analyze(a.format,Path(a.out_dir),Path(a.inputs_dir) if a.inputs_dir else None,a.with_tools)

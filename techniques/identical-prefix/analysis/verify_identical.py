#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Identical-Prefix collision analyzer

Analyzes:
- Binary collision pairs (c1.bin / c2.bin) before appendix
- Final text pairs (result_A.txt / result_B.txt) after appendix
- MD5 preservation after appending common suffix (Merkle-Damgård property)
- Prefix and appendix content
- First differing bytes in collision blocks
- Hexdumps of collision regions

Outputs in OUT_DIR:
- analysis.md
- c1.head.hex / c2.head.hex (first 96 bytes of binary collision)
- collision_block.hex (differing region hexdump)
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Optional, Tuple, List


# ------------- helpers -------------------------------------------------------
def md5sum(b: bytes) -> str:
    return hashlib.md5(b).hexdigest()


def sha256sum(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def hexdump_head(data: bytes, n: int = 96) -> str:
    out = []
    for off in range(0, min(len(data), n), 16):
        chunk = data[off:off + 16]
        hexs = " ".join(f"{bb:02x}" for bb in chunk)
        asc = "".join(chr(bb) if 32 <= bb < 127 else "." for bb in chunk)
        out.append(f"{off:08x}  {hexs:<47}  |{asc}|")
    return "\n".join(out)


def hexdump_region(data: bytes, start: int, length: int) -> str:
    """Hexdump a specific region of data"""
    out = []
    end = min(start + length, len(data))
    for off in range(start, end, 16):
        chunk = data[off:min(off + 16, end)]
        hexs = " ".join(f"{bb:02x}" for bb in chunk)
        asc = "".join(chr(bb) if 32 <= bb < 127 else "." for bb in chunk)
        out.append(f"{off:08x}  {hexs:<47}  |{asc}|")
    return "\n".join(out)


def hexdump_with_diff_markers(data: bytes, other: bytes, max_bytes: int = 384) -> List[str]:
    """Generate hexdump with difference markers on the right"""
    lines = []
    for offset in range(0, min(len(data), max_bytes), 16):
        hex_parts = []
        ascii_parts = []
        diff_markers = []

        for i in range(16):
            idx = offset + i
            if idx < len(data):
                byte = data[idx]
                hex_parts.append(f"{byte:02X}")

                # ASCII representation
                if 32 <= byte <= 126:
                    ascii_parts.append(chr(byte))
                else:
                    ascii_parts.append('.')

                # Diff marker
                if idx < len(other):
                    if byte != other[idx]:
                        diff_markers.append('X')
                    else:
                        diff_markers.append('.')
                else:
                    diff_markers.append('.')
            else:
                hex_parts.append("  ")
                ascii_parts.append(" ")
                diff_markers.append(" ")

        # Format: offset: hex1 hex2 ... hex8  hex9 ... hex16  ascii  diff
        hex_left = " ".join(hex_parts[0:8])
        hex_right = " ".join(hex_parts[8:16])
        ascii_str = "".join(ascii_parts)
        diff_str = "".join(diff_markers)

        lines.append(f"{offset:02X}: {hex_left}  {hex_right}  {ascii_str}  {diff_str}")

    return lines


def first_diff(a: bytes, b: bytes) -> Optional[Tuple[int, int, int]]:
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return i, a[i], b[i]
    return None if len(a) == len(b) else (n, -1, -1)


def all_diffs_in_range(a: bytes, b: bytes, start: int, end: int) -> List[Tuple[int, int, int]]:
    """Find all differing bytes in a range"""
    out = []
    n = min(len(a), len(b), end)
    for i in range(start, n):
        if a[i] != b[i]:
            out.append((i, a[i], b[i]))
    return out


def find_collision_block_bounds(a: bytes, b: bytes, first_diff_offset: int) -> Tuple[int, int]:
    """
    Find the bounds of the collision block.
    FastColl typically produces a 128-byte collision block starting at the first difference.
    """
    # FastColl collision blocks are typically 128 bytes
    start = first_diff_offset
    # Round down to nearest 64-byte boundary for better visualization
    start = (start // 64) * 64
    end = start + 128

    # Extend end to include all differences
    i = end
    while i < min(len(a), len(b)) and i < start + 256:
        if a[i] != b[i]:
            end = i + 64
        i += 1

    return start, min(end, len(a), len(b))


# ------------- main analysis -------------------------------------------------
def analyze(out_dir: Path) -> None:
    out_dir = out_dir.resolve()

    # Check for required files
    c1_path = out_dir / "c1.bin"
    c2_path = out_dir / "c2.bin"
    result_a_path = out_dir / "result_A.txt"
    result_b_path = out_dir / "result_B.txt"
    prefix_path = out_dir / "prefix.txt"
    appendix_path = out_dir / "appendix.txt"

    missing = []
    for p in [c1_path, c2_path, result_a_path, result_b_path]:
        if not p.exists():
            missing.append(p.name)

    if missing:
        raise SystemExit(f"Missing required files in {out_dir}: {', '.join(missing)}")

    # Read files
    c1_bin = c1_path.read_bytes()
    c2_bin = c2_path.read_bytes()
    result_a = result_a_path.read_bytes()
    result_b = result_b_path.read_bytes()

    prefix = prefix_path.read_text() if prefix_path.exists() else "(no prefix.txt)"
    appendix = appendix_path.read_text() if appendix_path.exists() else "(no appendix.txt)"

    # Binary files analysis (before appendix)
    md5_c1 = md5sum(c1_bin)
    md5_c2 = md5sum(c2_bin)
    sha_c1 = sha256sum(c1_bin)
    sha_c2 = sha256sum(c2_bin)
    size_c1 = len(c1_bin)
    size_c2 = len(c2_bin)

    # Final files analysis (after appendix)
    md5_a = md5sum(result_a)
    md5_b = md5sum(result_b)
    sha_a = sha256sum(result_a)
    sha_b = sha256sum(result_b)
    size_a = len(result_a)
    size_b = len(result_b)

    # Find differences
    fd_bin = first_diff(c1_bin, c2_bin)
    if not fd_bin:
        raise SystemExit("Binary files are identical (unexpected)")

    off_bin, b1, b2 = fd_bin

    # Find collision block bounds
    coll_start, coll_end = find_collision_block_bounds(c1_bin, c2_bin, off_bin)
    coll_diffs = all_diffs_in_range(c1_bin, c2_bin, coll_start, coll_end)

    # Verify Merkle-Damgård property
    md5_preserved = (md5_c1 == md5_c2) and (md5_a == md5_b)

    # Save hexdumps
    (out_dir / "c1.head.hex").write_text(hexdump_head(c1_bin, 96))
    (out_dir / "c2.head.hex").write_text(hexdump_head(c2_bin, 96))

    # Save collision block hexdump
    collision_hex = []
    collision_hex.append("=== Collision block in c1.bin ===\n")
    collision_hex.append(hexdump_region(c1_bin, coll_start, coll_end - coll_start))
    collision_hex.append("\n\n=== Collision block in c2.bin ===\n")
    collision_hex.append(hexdump_region(c2_bin, coll_start, coll_end - coll_start))
    (out_dir / "collision_block.hex").write_text("\n".join(collision_hex))

    # Build analysis.md
    lines: List[str] = []

    lines.append("# Identical-Prefix MD5 Collision — Analysis\n")

    lines.append("## Overview\n")
    lines.append("This technique uses HashClash's `md5_fastcoll` to generate two files with:")
    lines.append("- **Identical prefix** (the input prefix)")
    lines.append("- **Different collision blocks** (128 bytes generated by md5_fastcoll)")
    lines.append("- **Identical MD5 hash**")
    lines.append("- **Different SHA-256 hash** (proving they are different files)\n")

    lines.append("## Prefix\n")
    lines.append("```")
    lines.append(prefix)
    lines.append("```\n")

    lines.append("## Binary Collision Files (before appendix)\n")
    lines.append(f"- **{c1_path.name}** — size: **{size_c1}** bytes")
    lines.append(f"- **{c2_path.name}** — size: **{size_c2}** bytes\n")

    lines.append("### Hashes (Binary)\n")
    lines.append("```")
    lines.append(f"MD5(c1.bin)    {md5_c1}")
    lines.append(f"MD5(c2.bin)    {md5_c2}")
    lines.append(f"MD5 match:     {md5_c1 == md5_c2}")
    lines.append("")
    lines.append(f"SHA256(c1.bin) {sha_c1}")
    lines.append(f"SHA256(c2.bin) {sha_c2}")
    lines.append(f"SHA256 differ: {sha_c1 != sha_c2}")
    lines.append("```\n")

    lines.append("### Collision Block Details\n")
    lines.append("```")
    lines.append(f"First difference at byte:    {off_bin} (0x{off_bin:X})")
    lines.append(f"  c1.bin[{off_bin}] = 0x{b1:02X}")
    lines.append(f"  c2.bin[{off_bin}] = 0x{b2:02X}")
    lines.append("")
    lines.append(f"Collision block region:      {coll_start}-{coll_end} ({coll_end - coll_start} bytes)")
    lines.append(f"Total differing bytes:       {len(coll_diffs)}")
    lines.append("```\n")

    if len(coll_diffs) <= 20:
        lines.append("### All Differing Bytes in Collision Block\n")
        lines.append("```")
        for i, x, y in coll_diffs:
            lines.append(f"  byte {i:5d} (0x{i:04X}):  {x:02X} -> {y:02X}")
        lines.append("```\n")
    else:
        lines.append("### First 20 Differing Bytes in Collision Block\n")
        lines.append("```")
        for i, x, y in coll_diffs[:20]:
            lines.append(f"  byte {i:5d} (0x{i:04X}):  {x:02X} -> {y:02X}")
        lines.append(f"  ... and {len(coll_diffs) - 20} more")
        lines.append("```\n")

    lines.append("---\n")

    lines.append("## Appendix (Common Suffix)\n")
    lines.append("```")
    lines.append(appendix)
    lines.append("```\n")

    lines.append("## Final Files (after appendix)\n")
    lines.append(f"- **{result_a_path.name}** — size: **{size_a}** bytes")
    lines.append(f"- **{result_b_path.name}** — size: **{size_b}** bytes\n")

    lines.append("### Hashes (Final)\n")
    lines.append("```")
    lines.append(f"MD5(result_A.txt)    {md5_a}")
    lines.append(f"MD5(result_B.txt)    {md5_b}")
    lines.append(f"MD5 match:           {md5_a == md5_b}")
    lines.append("")
    lines.append(f"SHA256(result_A.txt) {sha_a}")
    lines.append(f"SHA256(result_B.txt) {sha_b}")
    lines.append(f"SHA256 differ:       {sha_a != sha_b}")
    lines.append("```\n")

    lines.append("## Merkle-Damgård Property Verification\n")
    lines.append("The MD5 hash function uses the Merkle-Damgård construction, which means:")
    lines.append("> **If MD5(A) = MD5(B), then MD5(A||C) = MD5(B||C)** for any suffix C\n")
    lines.append("```")
    lines.append(f"MD5 preserved after appending common suffix: {md5_preserved}")
    lines.append("")
    lines.append(f"Before: MD5(c1.bin) = {md5_c1}")
    lines.append(f"        MD5(c2.bin) = {md5_c2}")
    lines.append(f"After:  MD5(result_A.txt) = {md5_a}")
    lines.append(f"        MD5(result_B.txt) = {md5_b}")
    lines.append("```\n")

    lines.append("---\n")

    # Add visual hexdump comparison
    lines.append("## Visual Hexdump Comparison\n")
    lines.append("Side-by-side comparison showing the collision structure:\n")
    lines.append("```")
    lines.append("Legend: '.' = identical byte, 'X' = different byte")
    lines.append("")
    lines.append("=== result_A.txt ===")
    lines.extend(hexdump_with_diff_markers(result_a, result_b))
    lines.append("")
    lines.append("=== result_B.txt ===")
    lines.extend(hexdump_with_diff_markers(result_b, result_a))
    lines.append("```\n")

    # Add structure breakdown
    lines.append("### Structure Breakdown\n")
    lines.append("```")
    lines.append("Bytes 0x00-0x3F (0-63):   PREFIX (readable text + padding)")
    lines.append(f"  0x00-0x20: \"{prefix.strip()}\"")
    lines.append("  0x21-0x3F: Null padding to 64-byte boundary")
    lines.append("")
    lines.append(f"Bytes 0x40-0xBF (64-191): COLLISION BLOCK (128 bytes)")
    lines.append("  Generated by md5_fastcoll")
    lines.append(f"  Only {len(coll_diffs)} bytes differ between the two files")
    hex_diffs = ", ".join(f"0x{i:02X}" for i, _, _ in coll_diffs)
    lines.append(f"  Differences at: {hex_diffs}")
    lines.append("")
    lines.append(f"Bytes 0xC0-EOF (192-{size_a}):  IDENTICAL SUFFIX ({size_a - 192} bytes)")
    lines.append("  \"--- Appendix (readable) ---\"")
    lines.append("  \"Course: 02232 Applied Cryptography (Fall 2025)\"")
    lines.append("  \"Note: Appending the SAME bytes to both files preserves...\"")
    lines.append("```\n")

    lines.append("---\n")
    lines.append("**Course:** 02232 Applied Cryptography (Fall 2025)")
    lines.append("**Note:** Appending the SAME bytes to both files preserves the MD5 collision (Merkle-Damgård).")

    # Write analysis
    (out_dir / "analysis.md").write_text("\n".join(lines))

    # Summary output
    print(f"[identical-prefix] Binary MD5: {md5_c1[:16]}... == {md5_c2[:16]}... | Final MD5: {md5_a[:16]}... == {md5_b[:16]}...")
    print(f"  Collision block: bytes {coll_start}-{coll_end} ({len(coll_diffs)} diffs)")
    print(f"  Merkle-Damgård preserved: {md5_preserved}")
    print(f"Wrote: {out_dir/'analysis.md'}, {out_dir/'c1.head.hex'}, {out_dir/'c2.head.hex'}, {out_dir/'collision_block.hex'}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out-dir", required=True, help="Output directory containing collision files")
    a = p.parse_args()
    analyze(Path(a.out_dir))

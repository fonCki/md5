#!/usr/bin/env python3
"""
pdf_wrap.py

Minimal PDF wrapper that embeds an arbitrary payload as an EmbeddedFile stream.
Produces a simple PDF with an EmbeddedFile file specification pointing to the
binary stream. The script can be used to wrap:
  prefix.bin + SA.bin + common_tail.bin  -> collision1.pdf
  prefix'.bin + SB.bin + common_tail.bin -> collision2.pdf

Usage:
  python3 pdf_wrap.py prefix.bin SA.bin common_tail.bin out.pdf
"""
import sys
from pathlib import Path

def read_concat(parts):
    data = b''.join([Path(p).read_bytes() for p in parts if Path(p).exists()])
    return data

def make_pdf(payload_bytes: bytes, visible_title: str = "Document"):
    # We'll create PDF objects and compute offsets.
    # Objects: 1 Catalog, 2 Pages, 3 Page, 4 EmbeddedFile stream, 5 Filespec, 6 Names
    objs = []

    # Object 1: Catalog
    obj1 = f"""1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
"""
    objs.append(obj1)

    # Object 2: Pages
    obj2 = f"""2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
"""
    objs.append(obj2)

    # Object 3: Page (empty page)
    obj3 = f"""3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 7 0 R >> >> /MediaBox [0 0 612 792]
/Contents 8 0 R /StructParents 0 >>
endobj
"""
    objs.append(obj3)

    # Object 7: simple font (Helvetica)
    obj7 = f"""7 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>
endobj
"""
    objs.append(obj7)

    # Object 8: page content that references the embedded file by name (not necessary to view)
    content_stream = f"BT /F1 24 Tf 72 720 Td ({visible_title}) Tj ET\n"
    obj8 = f"""8 0 obj
<< /Length {len(content_stream.encode('latin1'))} >>
stream
{content_stream}
endstream
endobj
"""
    objs.append(obj8)

    # Object 4: EmbeddedFile stream (the payload)
    # Build a PDF stream containing the payload bytes
    payload_len = len(payload_bytes)
    # We will avoid binary-to-text translation; embed raw bytes in the stream.
    stream_header = f"""4 0 obj
<< /Type /EmbeddedFile /Length {payload_len} >>
stream
"""
    stream_footer = "\nendstream\nendobj\n"
    objs.append((stream_header, payload_bytes, stream_footer))

    # Object 5: Filespec referencing the embedded file stream
    obj5 = f"""5 0 obj
<< /Type /Filespec /F ({visible_title}) /EF << /F 4 0 R >> >>
endobj
"""
    objs.append(obj5)

    # Object 6: Names tree for EmbeddedFiles
    obj6 = f"""6 0 obj
<< /Names [(Embedded) 5 0 R] >>
endobj
"""
    objs.append(obj6)

    # Build PDF by writing header, objects, then xref & trailer.
    buf = bytearray()
    buf.extend(b"%PDF-1.7\n%\xE2\xE3\xCF\xD3\n")
    offsets = []
    for item in objs:
        offsets.append(len(buf))
        if isinstance(item, tuple):
            header, payload, footer = item
            buf.extend(header.encode('latin1'))
            buf.extend(payload)
            buf.extend(footer.encode('latin1'))
        else:
            buf.extend(item.encode('latin1'))

    # xref
    xref_offset = len(buf)
    buf.extend(b"xref\n0 %d\n" % (len(offsets) + 1))
    buf.extend(b"0000000000 65535 f \n")
    for off in offsets:
        buf.extend(f"{off:010d} 00000 n \n".encode('latin1'))

    # trailer
    trailer = f"""trailer
<< /Size {len(offsets)+1} /Root 1 0 R /Names 6 0 R >>
startxref
{xref_offset}
%%EOF
"""
    buf.extend(trailer.encode('latin1'))
    return bytes(buf)

def main():
    if len(sys.argv) != 5:
        print("Usage: python3 pdf_wrap.py prefix.bin SA.bin common_tail.bin out.pdf")
        sys.exit(1)
    prefix, sa, common_tail, out_pdf = sys.argv[1:]
    parts = [prefix, sa, common_tail]
    payload = read_concat(parts)
    title = Path(prefix).name  # make visible title per input filename for easy diff
    pdf_bytes = make_pdf(payload, visible_title=title)
    Path(out_pdf).write_bytes(pdf_bytes)
    print(f"Wrote {out_pdf}: {len(pdf_bytes)} bytes (embedded payload {len(payload)} bytes)")

if __name__ == "__main__":
    main()

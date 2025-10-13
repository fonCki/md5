#!/usr/bin/env python3
# PDF MD5 collision builder (corkami-style) with self-contained dummy.pdf
# Ange Albertini 2018-2021 (original idea); this variant:
# - generates a valid dummy.pdf on the fly (1 blank page, correct xref)
# - fixes adjustPDF() to operate on bytes only
# - tolerates mutool vs mutool.exe
# - uses a bytes-keyed mapping for bytes template formatting

import os, sys, shutil, hashlib

# --- choose mutool binary ----------------------------------------------------
def pick_mutool():
  for cand in ("mutool", "mutool.exe"):
    if shutil.which(cand):
      return cand
  return "mutool"  # last resort; will error clearly later if missing

MUTOOL = pick_mutool()

# --- tiny helpers ------------------------------------------------------------
def EnclosedString(d: bytes, starts: bytes, ends: bytes) -> bytes:
  off = d.find(starts)
  if off < 0:
    return b""
  off += len(starts)
  end = d.find(ends, off)
  return d[off:end if end >= 0 else len(d)]

def getCount(d: bytes) -> int:
  s = EnclosedString(d, b"/Count ", b"/")
  return int(s)

def procreate(lst) -> bytes:
  # join object refs as "... 0 R ..."
  return b" 0 R ".join(lst) + b" 0 R"

# --- generate a minimal valid 1-page PDF (dummy.pdf) -------------------------
def write_minimal_dummy_pdf(path: str):
  """
  Writes a small, valid PDF with:
    1 0 obj: Catalog -> Pages 2 0 R
    2 0 obj: Pages /Count 1 /Kids [3 0 R]
    3 0 obj: Page /Parent 2 0 R /MediaBox [0 0 1 1] /Contents 4 0 R
    4 0 obj: empty stream
  Proper xref + trailer + startxref included.
  """
  buf = bytearray()
  def w(b): buf.extend(b)
  def tell(): return len(buf)

  w(b"%PDF-1.4\n")
  offsets = {}

  offsets[1] = tell()
  w(b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")

  offsets[2] = tell()
  w(b"2 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n")

  offsets[3] = tell()
  w(b"3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1 1] /Contents 4 0 R /Resources <<>> >>\nendobj\n")

  offsets[4] = tell()
  w(b"4 0 obj\n<< /Length 0 >>\nstream\n\nendstream\nendobj\n")

  startxref = tell()
  w(b"xref\n")
  w(b"0 5\n")
  w(b"0000000000 65535 f \n")
  for i in range(1, 5):
    w(("%010d 00000 n \n" % offsets[i]).encode("ascii"))
  w(b"trailer\n<< /Root 1 0 R /Size 5 >>\nstartxref\n")
  w(("%d\n" % startxref).encode("ascii"))
  w(b"%%EOF\n")

  with open(path, "wb") as f:
    f.write(buf)

# --- fix xref in-place using bytes only --------------------------------------
def adjustPDF(contents: bytes) -> bytes:
  """
  Dumb xref fix for old-school xref (no holes), with hardcoded LF.
  Operates on BYTES only (no mixing with str).
  """
  startXREF = contents.find(b"\nxref\n0 ") + 1
  endXREF = contents.find(b" \n\n", startXREF) + 1
  origXref = contents[startXREF:endXREF]
  objCount = int(origXref.splitlines()[1].split(b" ")[1])
  print("object count: %i" % objCount)

  xrefLines = [
    b"xref",
    b"0 %i" % objCount,
    b"0000000000 00001 f "
  ]

  i = 1
  while i < objCount:
    off = contents.find(b"\n%i 0 obj\n" % i) + 1
    xrefLines.append(b"%010i 00000 n " % (off))
    i += 1

  xref = b"\n".join(xrefLines)

  try:
    assert len(xref) == len(origXref)
  except AssertionError:
    print("<:", repr(origXref))
    print(">:", repr(xref))

  contents = contents[:startXREF] + xref + contents[endXREF:]

  startStartXref = contents.find(b"\nstartxref\n", endXREF) + len(b"\nstartxref\n")
  endStartXref = contents.find(b"\n%%%%EOF", startStartXref)
  contents = contents[:startStartXref] + (b"%d" % startXREF) + contents[endStartXref:]
  return contents

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
if len(sys.argv) != 3:
  print("PDF MD5 collider")
  print("Usage: pdf.py <file1.pdf> <file2.pdf>")
  sys.exit(2)

in1, in2 = sys.argv[1], sys.argv[2]

# Create a proper dummy.pdf locally (self-contained)
write_minimal_dummy_pdf("dummy.pdf")

# Normalize inputs via mutool (merge each to flatten quirks)
os.system(f'{MUTOOL} merge -o first.pdf {in1}')
os.system(f'{MUTOOL} merge -o second.pdf {in2}')
os.system(f'{MUTOOL} merge -o merged.pdf dummy.pdf {in1} {in2}')

with open("first.pdf", "rb") as f:
  d1 = f.read()
with open("second.pdf", "rb") as f:
  d2 = f.read()
with open("merged.pdf", "rb") as f:
  dm = f.read()

COUNT1 = getCount(d1)
COUNT2 = getCount(d2)

kids = EnclosedString(dm, b"/Kids[", b"]")
# merged.pdf was built as: dummy + file1 + file2
# skip first kid (the dummy), and drop trailing " 0 R"
pages = kids[:-4].split(b" 0 R ")[1:]

template = b"""%%PDF-1.4

1 0 obj
<<
  /Type /Catalog
  %% retain alignment comments; merging/cleaning will strip comments
  /MD5_is__ /REALLY_dead_now__
  /Pages 2 0 R
  /Fakes 3 0 R
  %% placeholders for UniColl collision blocks
  /0123456789ABCDEF0123456789ABCDEF012
  /0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0
>>
endobj

2 0 obj
<</Type/Pages/Count %(COUNT2)i/Kids[%(KIDS2)s]>>
endobj

3 0 obj
<</Type/Pages/Count %(COUNT1)i/Kids[%(KIDS1)s]>>
endobj

%% overwritten - was a fake page to fool merging
4 0 obj
<< >>
endobj

"""

KIDS1 = procreate(pages[:getCount(d1)])
KIDS2 = procreate(pages[getCount(d1):])

# IMPORTANT: bytes template -> mapping must use BYTES KEYS
mapping = {
  b"COUNT1": COUNT1,
  b"COUNT2": COUNT2,
  b"KIDS1":  KIDS1,
  b"KIDS2":  KIDS2,
}
contents = template % mapping

# adjust /Parent for the first block of pages; COUNT1 replacements
contents += dm[dm.find(b"5 0 obj"):].replace(b"/Parent 2 0 R", b"/Parent 3 0 R", COUNT1)

# xref fix (bytes-safe)
contents = adjustPDF(contents)

with open("hacked.pdf", "wb") as f:
  f.write(contents)

# let mutool normalize objects/xref; -gggg like original
os.system(f"{MUTOOL} clean -gggg hacked.pdf cleaned.pdf")

with open("cleaned.pdf", "rb") as f:
  cleaned = f.read()

# some mutool versions produce slightly different offsets; normalize as in original
cleaned = cleaned.replace(
  b" 65536 f \n0000000016 00000 n \n",
  b" 65536 f \n0000000018 00000 n \n",
  1)

with open("pdf1.bin", "rb") as f:
  prefix1 = f.read()
with open("pdf2.bin", "rb") as f:
  prefix2 = f.read()

file1 = prefix1 + b"\n" + cleaned[192:]
file2 = prefix2 + b"\n" + cleaned[192:]

with open("collision1.pdf", "wb") as f:
  f.write(file1)
with open("collision2.pdf", "wb") as f:
  f.write(file2)

# cleanup intermediates
for tmp in ("first.pdf","second.pdf","merged.pdf","hacked.pdf","cleaned.pdf","dummy.pdf"):
  try: os.remove(tmp)
  except OSError: pass

# verify MD5s match
md5 = hashlib.md5(file1).hexdigest()
assert md5 == hashlib.md5(file2).hexdigest()

# show some info (non-fatal if mutool lacks -X)
print()
os.system(f"{MUTOOL} info -X collision1.pdf")
print("\n")
os.system(f"{MUTOOL} info -X collision2.pdf")
print()
print("MD5:", md5)
print("Success!")
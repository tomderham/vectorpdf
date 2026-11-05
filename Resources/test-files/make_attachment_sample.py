"""Writes attachment-sample.pdf: two pages with five embedded files, for the Attachments tab.

Four files are attached to the document (/EmbeddedFiles): a CSV, a text file, a PNG and an XML
e-invoice, which is also the document's associated file (/AF), as ZUGFeRD and Factur-X invoices
list theirs. A fifth is attached to page 2 by a file attachment annotation.

Usage: python3 Resources/test-files/make_attachment_sample.py Resources/test-files
"""
import sys, zlib, struct
from pathlib import Path

out = Path(sys.argv[1]) / "attachment-sample.pdf"

def png(w, h):
    raw = b"".join(b"\x00" + bytes(v for x in range(w) for v in (x * 255 // w, y * 255 // h, 160)) for y in range(h))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")

files = [
    ("quantities.csv", "text/csv", b"Item,Qty,Unit\nConcrete,42,m3\nRebar,3.5,t\nFormwork,120,m2\n", "Bill of quantities for level 2"),
    ("factur-x.xml", "text/xml", b'<?xml version="1.0" encoding="UTF-8"?>\n<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100">\n  <!-- Sample e-invoice data -->\n</rsm:CrossIndustryInvoice>\n', "Electronic invoice data"),
    ("site-photo.png", "image/png", png(64, 40), None),
    ("readme.txt", "text/plain", b"This file is attached to the document.\n", "Read me first"),
]
annot_file = ("inspection-notes.txt", "text/plain", b"Crack observed at gridline C4.\nRecheck after curing.\n", "Inspection notes")

objs = {}
def esc(s): return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
def fspec(num, ef, name, desc):
    d = f"<< /Type /Filespec /F ({esc(name)}) /UF ({esc(name)}) /EF << /F {ef} 0 R >>"
    if desc: d += f" /Desc ({esc(desc)})"
    objs[num] = (d + " >>").encode()
def efile(num, mime, data):
    objs[num] = (f"<< /Type /EmbeddedFile /Subtype /{mime.replace('/', '#2F')} /Length {len(data)} /Params << /Size {len(data)} /ModDate (D:20261105120000Z) >> >>\nstream\n").encode() + data + b"\nendstream"

n = 10
names, af = [], None
for name, mime, data, desc in files:
    efile(n + 1, mime, data); fspec(n, n + 1, name, desc)
    names.append((name, n))
    if name == "factur-x.xml": af = n
    n += 2
efile(n + 1, annot_file[1], annot_file[2]); fspec(n, n + 1, annot_file[0], annot_file[3]); annot_fs = n
n += 2

font = 5
objs[font] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
def content(num, lines):
    s = "BT /F1 20 Tf 72 720 Td " + " ".join(f"({esc(l)}) Tj 0 -30 Td" for l in lines) + " ET"
    objs[num] = f"<< /Length {len(s)} >>\nstream\n{s}\nendstream".encode()
content(6, ["Attachment test, page 1", "Open the paperclip tab in the sidebar.", "Four files are attached to the document."])
content(7, ["Attachment test, page 2", "The paperclip icon below holds a file", "attached to this page."])
objs[8] = f"<< /Type /Annot /Subtype /FileAttachment /Rect [72 560 92 584] /Name /PushPin /FS {annot_fs} 0 R /Contents (Inspection notes) /C [1 0.6 0] >>".encode()
objs[3] = f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 {font} 0 R >> >> /Contents 6 0 R >>".encode()
objs[4] = f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 {font} 0 R >> >> /Contents 7 0 R /Annots [8 0 R] >>".encode()
objs[2] = b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>"
tree = " ".join(f"({esc(k)}) {v} 0 R" for k, v in sorted(names))
objs[1] = f"<< /Type /Catalog /Pages 2 0 R /Names << /EmbeddedFiles << /Names [{tree}] >> >> /AF [{af} 0 R] >>".encode()

body = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
for num in sorted(objs):
    offsets[num] = len(body)
    body += f"{num} 0 obj\n".encode() + objs[num] + b"\nendobj\n"
size = max(objs) + 1
xref = len(body)
body += f"xref\n0 {size}\n".encode() + b"0000000000 65535 f \n"
for i in range(1, size):
    body += (f"{offsets[i]:010d} 00000 n \n" if i in offsets else "0000000000 65535 f \n").encode()
body += f"trailer\n<< /Size {size} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
out.write_bytes(body)

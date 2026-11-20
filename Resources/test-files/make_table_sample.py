"""Writes table-sample.pdf: a ruled table whose header cells are shaded, the way Word lays out
the tables of many specifications. Each header cell's shading is drawn just before its text, so
MuPDF puts every header cell in a text block of its own; the body rows' cells share a block.

Usage: python3 Resources/test-files/make_table_sample.py Resources/test-files
"""
import sys
from pathlib import Path

out = Path(sys.argv[1]) / "table-sample.pdf"

columns = [(36, 121), (121, 189), (189, 247), (247, 576)]
header = ["Field", "Size (Octets)", "Value (Hex)", "Description"]
body = [
    ["Attribute ID", "1", "0x04", "Identifies the type of attribute."],
    ["Length", "1", "Variable", "Length of the following fields in the attribute."],
    ["Domain Name", "Variable", "Variable", "Domain name of the network."],
]
top, row_height = 200, 18

def esc(s): return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
def y(page_y): return 792 - page_y   # PDF space runs up from the bottom of the page
def text(x, row, s, font):
    return f"BT /{font} 9 Tf {x + 5} {y(top + row * row_height + 12)} Td ({esc(s)}) Tj ET\n"
def rule(x0, y0, x1, y1):   # borders drawn as thin filled rectangles, as Word does
    return f"{x0} {y(y1)} {x1 - x0} {y1 - y0} re f\n"

ops = "BT /F1 10 Tf 230 " + str(y(top - 12)) + " Td (Table 1. Domain Name attribute) Tj ET\n"
for (x0, x1), label in zip(columns, header):
    ops += f"q 0.85 g {x0} {y(top + row_height)} {x1 - x0} {row_height} re f Q\n"
    ops += text(x0, 0, label, "F2")
for r, cells in enumerate(body, start=1):
    for (x0, _), s in zip(columns, cells):
        ops += text(x0, r, s, "F1")
rows = len(body) + 1
for r in range(rows + 1):
    ops += rule(36, top + r * row_height, 576, top + r * row_height + 0.5)
for x in [c[0] for c in columns] + [576]:
    ops += rule(x, top, x + 0.5, top + rows * row_height)

content = ops.encode()
objs = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R"
    b" /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>",
    b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>",
]
pdf = b"%PDF-1.4\n"
offsets = []
for i, body_bytes in enumerate(objs, start=1):
    offsets.append(len(pdf))
    pdf += b"%d 0 obj\n" % i + body_bytes + b"\nendobj\n"
xref = len(pdf)
pdf += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
pdf += b"".join(b"%010d 00000 n \n" % o for o in offsets)
pdf += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
out.write_bytes(pdf)

"""Writes layer-configurations-sample.pdf: one page with three layers and alternative layer
configurations (/OCProperties /Configs), for the Layers tab's configuration menu.

The default configuration is named "Everything" and shows every layer. "Architecture Only" shows
one, "Electrical Plot" shows two and lists the layers in reverse order, and the last is unnamed,
so it appears as "Configuration 3".

Usage: python3 Resources/test-files/make_layer_configurations_sample.py Resources/test-files
"""
import sys
from pathlib import Path

content = b"""BT /F1 20 Tf 50 740 Td (Layer configurations sample) Tj ET
/OC /L1 BDC 0 0 1 rg 50 450 200 200 re f BT /F1 14 Tf 60 420 Td (Architecture \\(blue\\)) Tj ET EMC
/OC /L2 BDC 1 0 0 rg 300 450 200 200 re f BT /F1 14 Tf 310 420 Td (Electrical \\(red\\)) Tj ET EMC
/OC /L3 BDC 0 0.6 0 rg 50 150 450 200 re f BT /F1 14 Tf 60 120 Td (Plot border \\(green\\)) Tj ET EMC
"""
objs = [
 b"<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R 6 0 R 7 0 R]"
 b" /D << /Name (Everything) /Order [5 0 R 6 0 R 7 0 R] /ON [5 0 R 6 0 R 7 0 R] >>"
 b" /Configs ["
 b" << /Name (Architecture Only) /BaseState /OFF /ON [5 0 R] /Order [5 0 R 6 0 R 7 0 R] >>"
 b" << /Name (Electrical Plot) /BaseState /OFF /ON [6 0 R 7 0 R] /Order [7 0 R 6 0 R 5 0 R] >>"
 b" << /BaseState /ON /OFF [7 0 R] >>"
 b" ] >> >>",
 b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
 b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 8 0 R >> /Properties << /L1 5 0 R /L2 6 0 R /L3 7 0 R >> >> >>",
 b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream",
 b"<< /Type /OCG /Name (Architecture) >>",
 b"<< /Type /OCG /Name (Electrical) >>",
 b"<< /Type /OCG /Name (Plot Border) >>",
 b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
]
out = bytearray(b"%PDF-1.7\n"); offs = []
for i, o in enumerate(objs, 1):
    offs.append(len(out)); out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
x = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs)+1)
for o in offs: out += b"%010d 00000 n \n" % o
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs)+1, x)
(Path(sys.argv[1]) / "layer-configurations-sample.pdf").write_bytes(out)

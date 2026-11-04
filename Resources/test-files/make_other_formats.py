"""Writes the non-PDF test fixtures: an EPUB, a CBZ, an FB2 and an XPS, all hand-made.

Usage: python3 Resources/test-files/make_other_formats.py Resources/test-files
"""
import struct, sys, zipfile, zlib
from pathlib import Path

out = Path(sys.argv[1])

def paragraphs(chapter, n):
    words = ("the river ran past the mill and the miller counted every sack of grain "
             "before the barges came down from the hills in the early light").split()
    paras = []
    for i in range(n):
        start = (i * 7 + chapter) % len(words)
        sentence = " ".join(words[start:] + words[:start])
        paras.append(sentence[0].upper() + sentence[1:] + ".")
    return paras

chapters = [("The Mill", 30), ("The Barges", 30), ("Zanzibar Harbour", 30)]

# EPUB 3 with a navigation document, so the outline has three chapters.
with zipfile.ZipFile(out / "sample.epub", "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    z.writestr("META-INF/container.xml", """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>""")
    items = "".join(f'<item id="c{i}" href="c{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(len(chapters)))
    spine = "".join(f'<itemref idref="c{i}"/>' for i in range(len(chapters)))
    z.writestr("OEBPS/content.opf", f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">vectorpdf-sample</dc:identifier><dc:title>The Mill on the River</dc:title>
    <dc:creator>VectorPDF</dc:creator><dc:language>en</dc:language>
  </metadata>
  <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>{items}</manifest>
  <spine>{spine}</spine>
</package>""")
    links = "".join(f'<li><a href="c{i}.xhtml">{t}</a></li>' for i, (t, _) in enumerate(chapters))
    z.writestr("OEBPS/nav.xhtml", f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
<body><nav epub:type="toc"><ol>{links}</ol></nav></body></html>""")
    for i, (title, n) in enumerate(chapters):
        body = "".join(f"<p>{p}</p>" for p in paragraphs(i, n))
        z.writestr(f"OEBPS/c{i}.xhtml", f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{title}</title></head>
<body><h1>{title}</h1>{body}</body></html>""")

# FB2 with two sections.
sections = "".join(
    f"<section><title><p>{t}</p></title>" + "".join(f"<p>{p}</p>" for p in paragraphs(i, 12)) + "</section>"
    for i, (t, _) in enumerate(chapters[:2]))
(out / "sample.fb2").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
<description><title-info><book-title>The Mill on the River</book-title><lang>en</lang></title-info></description>
<body>{sections}</body></FictionBook>""", encoding="utf-8")

# CBZ: three plain pages, each a different colour with a darker band, as PNGs.
def png(width, height, colour, band):
    rows = b""
    for y in range(height):
        c = band if height // 3 <= y < 2 * height // 3 else colour
        rows += b"\x00" + bytes(c) * width
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))
with zipfile.ZipFile(out / "sample.cbz", "w") as z:
    for i, (colour, band) in enumerate([((230, 90, 80), (120, 30, 30)), ((90, 170, 230), (20, 60, 120)), ((120, 200, 120), (30, 90, 30))]):
        z.writestr(f"page{i + 1:02}.png", png(400, 600, colour, band))

# XPS: two fixed pages of vector paths (no text, so no fonts to embed).
with zipfile.ZipFile(out / "sample.xps", "w") as z:
    z.writestr("[Content_Types].xml", """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="fdseq" ContentType="application/vnd.ms-package.xps-fixeddocumentsequence+xml"/>
  <Default Extension="fdoc" ContentType="application/vnd.ms-package.xps-fixeddocument+xml"/>
  <Default Extension="fpage" ContentType="application/vnd.ms-package.xps-fixedpage+xml"/>
</Types>""")
    z.writestr("_rels/.rels", """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="r1" Type="http://schemas.microsoft.com/xps/2005/06/fixedrepresentation" Target="/FixedDocSeq.fdseq"/>
</Relationships>""")
    z.writestr("FixedDocSeq.fdseq", """<FixedDocumentSequence xmlns="http://schemas.microsoft.com/xps/2005/06"><DocumentReference Source="/Documents/1/FixedDoc.fdoc"/></FixedDocumentSequence>""")
    z.writestr("Documents/1/FixedDoc.fdoc", """<FixedDocument xmlns="http://schemas.microsoft.com/xps/2005/06"><PageContent Source="Pages/1.fpage"/><PageContent Source="Pages/2.fpage"/></FixedDocument>""")
    for n, fill in [(1, "#FF3366CC"), (2, "#FFCC6633")]:
        z.writestr(f"Documents/1/Pages/{n}.fpage", f"""<FixedPage xmlns="http://schemas.microsoft.com/xps/2005/06" Width="816" Height="1056" xml:lang="en">
  <Path Data="M 96,96 L 720,96 L 720,400 L 96,400 Z" Fill="{fill}"/>
  <Path Data="M 96,500 L 720,960" Stroke="#FF000000" StrokeThickness="4"/>
</FixedPage>""")

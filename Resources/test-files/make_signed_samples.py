#!/usr/bin/env python3
"""Makes signed PDFs for the signature validation tests, with the openssl command-line tool.

    python3 make_signed_samples.py

Writes, beside this script:
- signed-sample-ca.pem: a test certificate authority, which tests treat as trusted
- signed-valid.pdf: one page signed (adbe.pkcs7.detached, SHA-256) by "VectorPDF Test Signer",
  whose certificate that authority issued
- signed-tampered.pdf: the same file with a byte of the signed page content changed
- signed-then-changed.pdf: the valid file with an incremental update saved after signing, adding
  document information (which the signature allows)
- signed-then-page-changed.pdf: the valid file with an incremental update replacing the signed
  page's text (which it doesn't)

The keys are thrown away, so nothing else can be signed with them.
"""

import os
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENTS_HEX = 16384  # room for the signature: 8 KB of DER
BYTE_RANGE_PLACEHOLDER = b"[0 /********** /********** /**********]"


def openssl(*args, cwd):
    subprocess.run(["openssl", *args], cwd=cwd, check=True, capture_output=True)


def make_certificates(work):
    openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "ca.key", "-out", "ca.pem",
            "-subj", "/CN=VectorPDF Test CA/O=VectorPDF Tests", "-days", "36500",
            "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign", cwd=work)
    openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", "signer.key", "-out", "signer.csr",
            "-subj", "/CN=VectorPDF Test Signer/O=VectorPDF Tests/emailAddress=signer@example.com", cwd=work)
    with open(os.path.join(work, "signer.ext"), "w") as f:
        f.write("basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,nonRepudiation\n")
    openssl("x509", "-req", "-in", "signer.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial",
            "-out", "signer.pem", "-days", "36500", "-extfile", "signer.ext", cwd=work)


def unsigned_pdf():
    """A one-page PDF with a signed signature field whose ByteRange and Contents are placeholders."""
    page_text = b"BT /F1 24 Tf 72 700 Td (Agreement between the parties) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [5 0 R] /SigFlags 3 >> >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R"
        b" /Resources << /Font << /F1 6 0 R >> >> /Annots [5 0 R] >>",
        b"<< /Length " + str(len(page_text)).encode() + b" >>\nstream\n" + page_text + b"\nendstream",
        b"<< /Type /Annot /Subtype /Widget /FT /Sig /T (Signature1) /Rect [72 600 272 650] /F 4 /P 3 0 R /V 7 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached /Name (VectorPDF Test Signer)"
        b" /Reason (Approval) /Location (Test) /M (D:20261116120000Z)"
        b" /ByteRange " + BYTE_RANGE_PLACEHOLDER + b" /Contents <" + b"0" * CONTENTS_HEX + b"> >>",
    ]
    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for i, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
    return bytes(out), xref


def sign(pdf, work):
    start = pdf.index(b"/Contents <") + len(b"/Contents ")
    end = start + CONTENTS_HEX + 2  # the < and >
    ranges = b"[0 %d %d %d]" % (start, end, len(pdf) - end)
    ranges = ranges[:-1] + b" " * (len(BYTE_RANGE_PLACEHOLDER) - len(ranges)) + b"]"
    pdf = pdf.replace(BYTE_RANGE_PLACEHOLDER, ranges, 1)
    with open(os.path.join(work, "signed-bytes.bin"), "wb") as f:
        f.write(pdf[:start] + pdf[end:])
    openssl("cms", "-sign", "-binary", "-in", "signed-bytes.bin", "-signer", "signer.pem", "-inkey", "signer.key",
            "-certfile", "ca.pem", "-outform", "DER", "-md", "sha256", "-out", "signature.der", cwd=work)
    with open(os.path.join(work, "signature.der"), "rb") as f:
        signature = f.read().hex().encode()
    assert len(signature) <= CONTENTS_HEX
    return pdf[:start + 1] + signature + b"0" * (CONTENTS_HEX - len(signature)) + pdf[end - 1:]


def updated(pdf, xref, num, body, trailer=b""):
    """The file with an incremental update after the signature, replacing or adding object `num`."""
    update = bytearray(b"%d 0 obj\n" % num + body + b"\nendobj\n")
    offset = len(pdf)
    new_xref = len(pdf) + len(update)
    update += b"xref\n%d 1\n%010d 00000 n \n" % (num, offset)
    update += b"trailer\n<< /Size 9 /Root 1 0 R%s /Prev %d >>\nstartxref\n%d\n%%%%EOF\n" % (trailer, xref, new_xref)
    return pdf + bytes(update)


def changed_after_signing(pdf, xref):
    """Adds a document information dictionary."""
    return updated(pdf, xref, 8, b"<< /Title (Changed after signing) >>", b" /Info 8 0 R")


def page_changed_after_signing(pdf, xref):
    """Replaces the page's text."""
    text = b"BT /F1 24 Tf 72 700 Td (Agreement cancelled) Tj ET"
    return updated(pdf, xref, 4, b"<< /Length %d >>\nstream\n" % len(text) + text + b"\nendstream")


def main():
    work = tempfile.mkdtemp()
    try:
        make_certificates(work)
        pdf, xref = unsigned_pdf()
        signed = sign(pdf, work)
        tampered = signed.replace(b"(Agreement between", b"(Agreemint between", 1)
        assert tampered != signed
        for name, data in [("signed-valid.pdf", signed), ("signed-tampered.pdf", tampered),
                           ("signed-then-changed.pdf", changed_after_signing(signed, xref)),
                           ("signed-then-page-changed.pdf", page_changed_after_signing(signed, xref))]:
            with open(os.path.join(HERE, name), "wb") as f:
                f.write(data)
        shutil.copy(os.path.join(work, "ca.pem"), os.path.join(HERE, "signed-sample-ca.pem"))
    finally:
        shutil.rmtree(work)


if __name__ == "__main__":
    main()

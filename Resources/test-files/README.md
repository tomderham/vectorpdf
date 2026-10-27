# Test files

PDFs used by the automated tests (`swift test`) and for trying the app by hand.

| File | Source | License |
| --- | --- | --- |
| `f1040.pdf` | IRS Form 1040, an AcroForm with text fields, checkboxes and radio buttons | US Government work, public domain |
| `lcms2-tutorial.pdf` | *Little CMS 2.19 — How to use the engine in your applications*, from the `doc/` folder of [Little CMS](https://github.com/mm2/Little-CMS) (also shipped in MuPDF's `thirdparty/lcms2`). 60 pages, embedded fonts, internal links | MIT, Copyright (c) 2023 Marti Maria Saguer |
| `password-protected-sample.pdf` | Made with `generate_password_protected_pdf.swift` | Same as VectorPDF |
| `url-link-sample.pdf` | Hand-written one-page PDF with a URI link | Same as VectorPDF |

Tests reach these through `Fixture` in `Tests/PDFEngineTests/TestFixtures.swift`, and fail (rather
than skip) when one is missing.

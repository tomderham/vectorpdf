# Test files

PDFs used by the automated tests (`swift test`) and for trying the app by hand. All are unmodified
originals except `ieee-802.11-draft-layout.pdf`.

| File | What it exercises | Source | License |
| --- | --- | --- | --- |
| `f1040.pdf` | AcroForm text fields, checkboxes, radio buttons | IRS Form 1040 | US Government work, public domain |
| `lcms2-tutorial.pdf` | 60 pages, embedded fonts, internal links | *Little CMS 2.19 tutorial*, `doc/` of [Little CMS](https://github.com/mm2/Little-CMS) (also in MuPDF's `thirdparty/lcms2`) | MIT, Copyright (c) 2023 Marti Maria Saguer |
| `federal-register-2024-00301.pdf` | Three narrow columns, footnotes, hyphenation | [Federal Register, 10 Jan 2024, pp. 1445–1447](https://www.govinfo.gov/content/pkg/FR-2024-01-10/pdf/2024-00301.pdf) | US Government work, public domain |
| `hr1968-ih.pdf` | Margin line numbers, fully justified lines, 99 pages | [H.R. 1968 (119th Congress), as introduced](https://www.govinfo.gov/content/pkg/BILLS-119hr1968ih/pdf/BILLS-119hr1968ih.pdf) | US Government work, public domain |
| `rfc9457.pdf` | Outline, internal links through named destinations | [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457.pdf) | IETF Trust Legal Provisions (copied in full, unmodified) |
| `nist-tn-2255.pdf` | Vector plots in colour, Greek letters and subscripts, outline | [NIST Technical Note 2255](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2255.pdf) | US Government work, not subject to copyright in the US |
| `ieee-802.11-draft-layout.pdf` | IEEE 802.11 draft layout: line numbers 1–65, frame-format tables with a numeric Order column, a bit-field figure | Two pages of an 802.11 draft with every letter replaced (see below) | Words removed; layout only |
| `password-protected-sample.pdf` | Password prompt | Made with `generate_password_protected_pdf.swift` | Same as VectorPDF |
| `url-link-sample.pdf` | A URI link | Hand-written | Same as VectorPDF |

## The 802.11 layout page

IEEE drafts can't be redistributed, but their layout is what VectorPDF has to handle best.
`scramble_text.js` keeps a document's layout and removes its words: every letter is replaced with
a random letter of similar width from the same font (chosen per occurrence, so the original can't
be recovered), while digits, punctuation and positions stay. Metadata, outlines and annotations are
dropped. To make another page:

```bash
mutool merge -o pages.pdf draft.pdf 118,124
mutool run Resources/test-files/scramble_text.js pages.pdf scrambled.pdf
```

Check the result has no identifying text left (`mutool draw -F txt scrambled.pdf`) before adding it.

## PDF Association test files

`pdf-differences/` holds unmodified files from the PDF Association's
[pdf-differences](https://github.com/pdf-association/pdf-differences) repository, at commit
`907fe96e52b73e491489eee545c47b119bf9989b`. They're under the Apache License 2.0, copied alongside
them as `LICENSE`. Only files a test can check without comparing pixels are here; the repository
asks that its screenshots aren't compared that way.

| File | What it exercises |
| --- | --- |
| `PageLabelsTest.pdf` | Roman, decimal, Arabic-script and long page labels, used for jumping to a page |
| `NegativeFontSize.pdf`, `Type3Test.pdf`, `VerticalText.pdf` | Text extraction from upside-down, Type 3 and vertical text |
| `PDF-versions1.pdf` to `PDF-versions3.pdf` | A version raised by the catalog, then by an incremental update; all are PDF 1.6 |
| `UnknownFilter-*.pdf` | A fake `/XXXDecode` filter on one kind of stream at a time, in a file claiming a future PDF version |

Tests reach these files through `Fixture` in `Tests/PDFEngineTests/TestFixtures.swift`, and fail
(rather than skip) when one is missing.

# VectorPDF

A fast, lightweight, native macOS PDF reader engineered for technical documents, large specifications, and academic papers. Built on Artifex's **MuPDF (Fitz)** rendering engine, Swift 6, AppKit, and SwiftUI.

---

## Features

**Reading & navigation**
- **Virtualized scrolling:** Only pages near the viewport are rendered; very long documents open without laying out every page up front. Single-page, two-page, and book (cover-offset) layouts, page rotation, and fit-width / fit-window zoom.
- **Display-list caching:** Compiled page display lists (`fz_display_list`) are replayed when re-rendering at a new zoom instead of re-parsing content streams.
- **Search:** Streaming full-text search with match case, whole word, and regular-expression options, plus a smart pattern builder for common formats.
- **Outline, thumbnails & history:** Table-of-contents tree, thumbnail grid (with drag-and-drop page reordering), and Back/Forward navigation history.
- **Reading themes:** Light, dark (luminance inversion that preserves hues), and sepia, using MuPDF pixmap operations.
- **Resume where you left off:** Last page and zoom are remembered per document.
- **Live reload:** Open documents reload when the file changes on disk.
- **Cloud-aware opening:** Detects iCloud Drive and third-party cloud-storage files (Google Drive, Dropbox, OneDrive, Box) and downloads evicted files before opening.
- **Text-to-speech and translation** of selected text, and Handoff of the current reading position.

**Cross-references**
- **Column-aware text selection** using structured text geometry (`fz_stext_page`), so selections in multi-column layouts don't pick up adjacent columns or margin line numbers.
- **Link peek:** Hold Command over an internal link (or Force Click it) to preview its target in a chrome-less popup that closes when you let go. The preview shows context suited to the target — a few lines for equations, the opening paragraph for sections, the top of a table or figure — identified from LaTeX (hyperref) destination names and the document outline.
- **Open in New Window:** Command-click a link, citation, equation, table, or figure reference (or choose Open in New Window from its context menu) to open its target in a separate window without losing your place.
- **Anchors:** Save text or area selections as named anchors and jump back to them from the Anchors menu.

**Workspace**
- **Native tabs and saved Tab Groups:** macOS window tabs, session restoration, and named groups that reopen several documents together. Favorites and recent documents.

**Markup & forms**
- **Annotations:** Highlight, underline, strikethrough, freehand ink, text boxes, callouts, and stamps, with an eraser and a color palette.
- **AcroForms & signatures:** Fill text fields, checkboxes, and comboboxes; place visual signature stamps.

**Engineering tools**
- **Measurement & takeoff:** Scale calibration, length, perimeter, area, and angle measurements stored in the PDF (ISO 32000 viewport), and a takeoff summary table.

**Editing & security**
- **Page management:** Rotate, delete, reorder, duplicate, insert blank or imported pages, extract pages, and split a PDF.
- **Redaction:** Region and find-and-redact (text, regex, SSN, credit card, email, phone, date) with true content removal.
- **Encryption:** Open password-protected PDFs and save copies encrypted with AES-256.
- **On-device OCR** of scanned pages using Apple Vision, making them searchable; highlights follow slanted text on skewed scans.

**Export & print**
- **Export:** Plain text, Word (.docx), SVG (one file per page, text as vector paths), and flattened PDF; annotation summary export; printing through MuPDF so output matches the on-screen rendering.

**Agent (optional)**
- **Document Q&A:** On-device semantic search over the open document using Apple's NaturalLanguage embeddings. Answer synthesis uses Apple Intelligence (on-device or Private Cloud Compute) when available; without it, the best-matching passages are shown instead. Requires a macOS release that supports these frameworks.

---

## Architecture

```
+---------------------------------------------------------------------------------+
|                                macOS App Layer                                  |
|   SwiftUI App Chrome • Multi-Window / Tabs • Session Manager • Settings         |
+---------------------------------------------------------------------------------+
          |                                                   |
+------------------------------+             +------------------------------------+
|     Navigation & Tools       |             |         Viewport & Canvas          |
|  - Table of Contents Tree    |             |  - NSViewRepresentable Canvas      |
|  - Interactive Thumbnails    |             |  - Quartz 2D Page Rendering        |
|  - Form Controls & Signing   |             |  - Spatial Column Selection Tool   |
|  - Link Peek & Anchors       |             |  - Search Highlight Overlays       |
+------------------------------+             +------------------------------------+
          |                                                   |
+---------------------------------------------------------------------------------+
|                       Core Engine & Services (Swift 6)                          |
|  - PDFDocumentCore (Document lifecycle, page geometry, AcroForm state)          |
|  - PDFRenderActor (Dedicated fz_context for tile rasterization)                 |
|  - PDFSearchActor (Dedicated fz_context for streaming async search)             |
|  - SpatialTextSelector (Column detection & character quad mapping)              |
|  - CrossReferenceResolver (Link destination resolution & target capture)       |
+---------------------------------------------------------------------------------+
                                         |
+---------------------------------------------------------------------------------+
|                          MuPDF C-Bridge (Fitz Core)                             |
|  - Vendored libmupdf (Self-contained static library / XCFramework)              |
|  - fz_context & fz_clone_context (One cloned context per background actor)   |
|  - fz_display_list (Pre-parsed vector display list replay for fast re-rendering)   |
|  - fz_stext_page (Structured text hierarchy: blocks, lines, chars, quads)       |
|  - pdf_annot & pdf_widget (AcroForms & standard PDF annotations)                |
+---------------------------------------------------------------------------------+
```

---

## System Requirements

- **Operating System:** macOS 14.0 (Sonoma) or later
- **Architecture:** Apple Silicon (arm64)
- **Toolchain:** Xcode 16.0+ or Swift 6.0+

---

## Building and Running

### 1. Initial Setup (Compile Vendored MuPDF)

On a fresh clone, run the vendor build script to compile MuPDF from its official source tarball:

```bash
./Vendor/build-mupdf.sh
```

*(This downloads the official source tarball, validates the pinned SHA-256 checksum, and compiles `Vendor/MuPDF.xcframework` in ~1–2 minutes).*

### 2. Build via Swift Package Manager

```bash
# Build the executable
swift build -c release

# Run automated tests
swift test
```

### 3. Build macOS Application Bundle

To assemble a signed `.app` bundle with application icon and metadata:

```bash
# Builds with macOS 27 SDK and Private Cloud Compute agent capabilities enabled by default:
./Scripts/build_app_bundle.sh release

# Or to build against the standard SDK:
./Scripts/build_app_bundle.sh release default
```

The output bundle will be generated at `./VectorPDF.app`.

### 4. Signed & Notarized DMG (maintainers)

```bash
./Scripts/build_dmg.sh
```

Signs with a Developer ID certificate, builds the DMG, notarizes it, and staples the ticket. Certificates and notarization credentials are read from the macOS Keychain (create a profile with `xcrun notarytool store-credentials`). Copy `Scripts/release.env.example` to `Scripts/release.env` (untracked) and set `SIGNING_IDENTITY` and `NOTARY_PROFILE`; the same variables can also be set in the environment to switch accounts.


---

## Vendored Dependencies

This project relies on **MuPDF** (version 1.28.5). To avoid committing a ~60MB binary to Git, `Vendor/MuPDF.xcframework` is built locally from source using `Vendor/build-mupdf.sh`.

To rebuild or update the vendored MuPDF version:

```bash
./Vendor/build-mupdf.sh [version]
```

See [Vendor/README.md](Vendor/README.md) for details on build options, version bumping, and Clang module configuration.

---

## License

VectorPDF is free software released under the **[GNU Affero General Public License v3.0 (AGPL-3.0)](LICENSE)**.

### Third-Party Attribution

- **MuPDF:** © Artifex Software, Inc. MuPDF is licensed under the GNU Affero General Public License (AGPL-3.0). Visit [https://mupdf.com](https://mupdf.com) for more information.

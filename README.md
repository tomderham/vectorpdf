# VectorPDF

A fast, native macOS PDF reader for technical papers, specifications, and drawings. Hold Command over a reference to an equation, figure, table, or citation and see it in place, without losing your page. Built on Artifex's **MuPDF (Fitz)** rendering engine, Swift 6, AppKit, and SwiftUI.

<!-- Demo GIFs (record with docs/demo/README.md):
![Hold Command over a reference to preview it](docs/link-peek.gif)
![Right-click a reference to another document open in a tab](docs/cross-doc.gif)
-->

**Status:** public beta. Free and open source ([AGPL-3.0](LICENSE)). Requires macOS 15 or later on Apple Silicon.

**Download:** the latest signed and notarized DMG is on the [Releases page](https://github.com/tomderham/vectorpdf/releases). The app checks GitHub for new releases (you can turn this off in Settings).

[User Guide](docs/guide/README.md) · [Privacy](PRIVACY.md) · [Contributing](CONTRIBUTING.md) · [Report a bug](https://github.com/tomderham/vectorpdf/issues)

---

## Features

**Reading & navigation**
- **Virtualized scrolling:** Only pages near the viewport are rendered; very long documents open without laying out every page up front. Single-page, two-page, and book (cover-offset) layouts, page rotation, and fit-width / fit-window zoom.
- **Display-list caching:** Compiled page display lists (`fz_display_list`) are replayed when re-rendering at a new zoom instead of re-parsing content streams.
- **Search:** Streaming full-text search with match case and whole word options. Smart Search matches across spaces, hyphens, dashes, line breaks, and quote styles, and can look past text you set as ignored patterns (regular expressions in Settings), such as comment tags inside technical documents.
- **Outline, thumbnails & history:** Table-of-contents tree, thumbnail grid (with drag-and-drop page reordering), and Back/Forward navigation history.
- **Reading themes:** Light, dark (luminance inversion that preserves hues), and sepia, using MuPDF pixmap operations.
- **Resume where you left off:** Last page and zoom are remembered per document.
- **Live reload:** Open documents reload when the file changes on disk.
- **Cloud-aware opening:** Detects iCloud Drive and third-party cloud-storage files (Google Drive, Dropbox, OneDrive, Box) and downloads evicted files before opening.
- **Text-to-speech and translation** of selected text, and Handoff of the current reading position.

**Cross-references**
- **Column-aware text selection** using structured text geometry (`fz_stext_page`), so selections in multi-column layouts don't pick up adjacent columns or margin line numbers.
- **Link peek:** Hold Command over an internal link (or Force Click it) to preview its target in a chrome-less popup that closes when you let go. The preview shows context suited to the target — a few lines for equations, the opening paragraph for sections, the top of a table or figure — identified from LaTeX (hyperref) destination names and the document outline.
- **References across documents:** Open related documents as tabs in one window, such as a standard and the specification it builds on, or a contract and its schedules. Right-click a plain-text reference like “Section 8.8.3 of [HTTP]” or “Clause 4.2 of the Master Agreement” to preview that section in the other tab and jump to it, matched against that document's outline (or its headings if it has none). Web links into an open document, such as IETF RFC links to rfc-editor.org, preview it there on Command-hover or Force Click.
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
- **Redaction:** Region and find-and-redact (text, regex, SSN, credit card, email, phone, date) with true content removal: text, image pixels, and line art under the region are deleted from the file, along with any annotations and form fields that touch it, and earlier revisions are not kept on save.
- **Encryption:** Open password-protected PDFs and save copies encrypted with AES-256.
- **On-device OCR** of scanned pages using Apple Vision, making them searchable; highlights follow slanted text on skewed scans.

**Export & print**
- **Export:** Plain text, Word (.docx), SVG (one file per page, text as vector paths), and flattened PDF; annotation summary export; printing through MuPDF so output matches the on-screen rendering.

**Agent (optional)**
- **Document Q&A:** On-device semantic search over the open document using Apple's NaturalLanguage embeddings. Answer synthesis uses Apple Intelligence on-device (macOS 26 or later), Private Cloud Compute (macOS 27, selectable in Settings, in builds signed with Apple's Private Cloud Compute entitlement), or an online model from OpenAI, Google Gemini, or OpenRouter with your own API key (macOS 27); without any of these, the best-matching passages are shown instead. See [PRIVACY.md](PRIVACY.md) for what leaves your Mac.

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

**To run:**
- **Operating System:** macOS 15 (Sequoia) or later. The Agent tab needs macOS 26 or later; Private Cloud Compute answers need macOS 27.
- **Architecture:** Apple Silicon (arm64)

**To build:**
- **Toolchain:** Xcode 27 (macOS 27 SDK, Swift 6). Older SDKs should build without the Private Cloud Compute option, but are not routinely tested.

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
./Scripts/build_app_bundle.sh release
```

With the macOS 27 SDK (Xcode 27) the build includes the Private Cloud Compute and online model options for the Agent tab, as do `swift build` and `swift run`. Answering with Private Cloud Compute also needs a build signed with Apple's managed entitlement (see section 5); without it the app answers on-device.

The output bundle will be generated at `./VectorPDF.app`.

### 4. Signed & Notarized DMG (maintainers)

```bash
./Scripts/build_dmg.sh
```

Signs with a Developer ID certificate, builds the DMG, notarizes it, and staples the ticket. Certificates and notarization credentials are read from the macOS Keychain (create a profile with `xcrun notarytool store-credentials`). Copy `Scripts/release.env.example` to `Scripts/release.env` (untracked) and set `SIGNING_IDENTITY` and `NOTARY_PROFILE`; the same variables can also be set in the environment to switch accounts. Set `PROVISIONING_PROFILE` to a Developer ID provisioning profile to enable the capabilities it grants, such as iCloud key-value storage for syncing reading positions.

Developer ID profiles don't include the Private Cloud Compute entitlement, so the DMG answers on-device (see section 5).

### 5. Build with Private Cloud Compute (your own Apple Developer account)

The released DMG answers on-device, because Apple grants the Private Cloud Compute entitlement only for App Store distribution and for TestFlight, ad hoc, and development builds. If your account has the [PCC entitlement](https://developer.apple.com/private-cloud-compute/), you can build a copy that uses it on your own Macs:

1. In Certificates, Identifiers & Profiles, create an explicit App ID (for example `com.example.vectorpdf`) with **Access to models on Private Cloud Compute** enabled, and register your Mac as a device.
2. Create a **macOS App Development** profile for that App ID, your Apple Development certificate, and your Mac, and download it.
3. Run:

```bash
./Scripts/build_pcc_dev.sh ~/Downloads/YourProfile.provisionprofile
```

The script checks that the profile grants PCC and includes this Mac, builds under the profile's bundle identifier, and signs with the matching certificate from your keychain. Then choose Private Cloud Compute in **Settings → AI Synthesis Engine**.


---

## Vendored Dependencies

This project relies on **MuPDF** (version 1.28.6, plus upstream fixes in `Vendor/patches/`). To avoid committing a ~60MB binary to Git, `Vendor/MuPDF.xcframework` is built locally from source using `Vendor/build-mupdf.sh`.

To rebuild or update the vendored MuPDF version:

```bash
./Vendor/build-mupdf.sh [version]
```

See [Vendor/README.md](Vendor/README.md) for details on build options, version bumping, and Clang module configuration.

---

## Privacy

VectorPDF has no accounts, analytics, or telemetry. Documents are processed on your Mac. The exceptions (update checks, iCloud sync of reading positions, and Private Cloud Compute or an online model if you choose one) are described in [PRIVACY.md](PRIVACY.md).

---

## Contributing

Bug reports with a sample PDF are the most useful contribution. See [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing, and code layout.

---

## License

VectorPDF is free software released under the **[GNU Affero General Public License v3.0 (AGPL-3.0)](LICENSE)**.

### Third-Party Attribution

- **MuPDF:** © Artifex Software, Inc. MuPDF is licensed under the GNU Affero General Public License (AGPL-3.0). Visit [https://mupdf.com](https://mupdf.com) for more information.
- **PDF Association test files:** `Resources/test-files/pdf-differences/` holds unmodified files from [pdf-association/pdf-differences](https://github.com/pdf-association/pdf-differences) under the Apache License 2.0, copied alongside them. They're used only for testing and aren't part of the app.
- **Foundation Models framework utilities:** © Apple Inc. and the Foundation Models project authors. `Sources/PDFEngine/ChatCompletionsLanguageModel.swift` is adapted from [apple/foundation-models-utilities](https://github.com/apple/foundation-models-utilities) under the Apache License 2.0; changes are marked in the file.

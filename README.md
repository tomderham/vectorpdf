# VectorPDF

A fast, lightweight, native macOS PDF reader engineered for technical documents, large specifications, and academic papers. Built on Artifex's **MuPDF (Fitz)** rendering engine, Swift 6, AppKit, and SwiftUI.

---

## Features

- **Instant Layout for Massive Documents:** Opens and lays out documents spanning 10,000+ pages in milliseconds using an adaptive continuous virtualized scroll pipeline.
- **Thread-Isolated Concurrency:** Employs cloned MuPDF contexts (`fz_clone_context`) across dedicated Swift actors for rendering and search. Background text extraction and indexing never stutter 120 FPS ProMotion viewport rendering.
- **Display-List Vector Tile Caching:** Caches compiled vector display lists (`fz_display_list`) to replay page operations during zoom and pan instead of re-parsing PDF content streams.
- **Column-Aware Spatial Selection:** Uses structured text geometry (`fz_stext_page`) to accurately select text across multi-column layouts without picking up adjacent columns or margin gutters.
- **Interactive Cross-References & Snapshots:** Detects internal PDF destinations and cross-references. Option-click opens targets in standalone snapshot inspector windows to cross-reference equations, figures, or citations without losing your reading location.
- **Native Tabs & Saved Tab Groups:** Full support for macOS window tabs, session restoration, and named Tab Groups that open multiple related documents together.
- **AcroForms & Signature Stamping:** Interactive form filling for text fields, checkboxes, and comboboxes, plus freehand visual signature stamping.
- **Adaptive Dark Mode:** Inverts document bitmaps in dark mode using SIMD-vectorized luminance remapping, with an app-level toggle to view true document colors whenever color fidelity is critical.
- **On-Device Semantic Search:** Embedded semantic indexing powered by Apple's NaturalLanguage framework for conceptual queries over document text.

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
|  - Interactive Thumbnails    |             |  - Quartz 2D Tile Rendering        |
|  - Form Controls & Signing   |             |  - Spatial Column Selection Tool   |
|  - Cross-Ref Snapshot HUD    |             |  - Search Highlight Overlay Quads  |
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
|  - fz_context & fz_clone_context (Multi-threaded lock-free memory management)   |
|  - fz_display_list (Pre-parsed vector display list replay for fast re-tiling)   |
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
./Scripts/build_app_bundle.sh release
```

The output bundle will be generated at `./VectorPDF.app`.

---

## Vendored Dependencies

This project relies on **MuPDF** (version 1.24.8). To avoid committing a ~60MB binary to Git, `Vendor/MuPDF.xcframework` is built locally from source using `Vendor/build-mupdf.sh`.

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

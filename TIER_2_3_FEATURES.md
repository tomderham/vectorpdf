# VectorPDF: Prospective Backlog Features

This document records prospective features identified during the architectural and roadmap review of VectorPDF. These features are cataloged here for future prioritization, evaluation, and design.

---

## Prospective Backlog Features

### 1. SyncTeX Integration (LaTeX Pair-Reading)
- **Description**: Bidirectional synchronization between LaTeX source code editors (VS Code, MacTeX, Sublime, TeXShop) and VectorPDF.
- **Capabilities**:
  - **Direct synchronization**: `⌘-Click` on any word in the PDF sends the corresponding `.tex` file line and column to the editor via URL scheme or IPC (`subl`, `code`, `texshop://...`).
  - **Reverse synchronization**: Command line invocation `vectorpdf --synctex-forward line:col:file.tex target.pdf` jumps directly to and highlights the target point in the PDF.
- **Implementation Notes**:
  - Leverage `synctex_parser.c` (standard TeXLive C library).

---

### 2. Engineering Blueprint Measurement & Scale Calibration
- **Description**: Precise distance, perimeter, and area measurement tools for architectural drawings, PCB layouts, and mechanical engineering schematics.
- **Capabilities**:
  - **Scale Calibration**: Calibrate drawing scale ratio (e.g. 1 in = 10 ft, 1 mm = 50 mm, or click two points of a known dimension to calibrate automatically).
  - **Dimension Measurement**: Measure linear distance between any two points with snapped perpendicular guidelines and dimension text overlays.
  - **Perimeter & Area Calculation**: Multi-point polygon tracing with live area and perimeter readouts.
  - **Angle Measurement**: Precise vertex angle inspector for mechanical and structural schematics.
- **Implementation Notes**:
  - Adheres to standard PDF `/Measure` and `/VP` (Viewport) dictionaries defined in ISO 32000.

---

### 3. Book Mode Cover Page Offset
- **Description**: Two-page spread formatting for bound books, journals, and manuals.
- **Capabilities**:
  - In Two-Page Mode, allow an option: "Show First Page Alone (Cover Page)".
  - Ensures left/right page symmetry aligns with recto/verso printing (odd pages on the right, even pages on the left).

---

### 4. Interactive Form Flattening (AcroForms to Static Graphics)
- **Description**: Permanently bake filled AcroForm fields into static vector page graphics.
- **Capabilities**:
  - File > **Flatten Form Fields...** or Save As option.
  - Replaces interactive widget annotations with static appearance streams (`/AP`), preventing further accidental edits when emailing or archiving signed forms.
- **Implementation Notes**:
  - MuPDF Fitz provides native `pdf_flatten_inheritable_page_items` and `pdf_drop_widgets` support.

---

### 5. Direct PDF Content Editing (In-Place Text & Image Modification) [LOW PRIORITY / HIGH RISK]
- **Description**: Direct editing of the underlying PDF content stream operators (`/Contents`) and embedded raster XObjects (`/XObject /Subtype /Image`), moving beyond overlay annotations to modify the document itself.
- **Capabilities**:
  - **In-Place Typo & Parameter Correction**: Click directly on existing text blocks to modify errata, fix typos, or update version strings, dates, and author metadata.
  - **Font Matching & Subset Handling**: Automatically detects font family, point size, and weight from the text block. For embedded font subsets that lack glyphs for new characters, substitutes matching system fonts (SF Pro, Helvetica, New York, Courier) and embeds new `/Font` descriptors into page `/Resources`.
  - **Bounded Paragraph Reflow**: Recomputes line breaks within the structured text block boundary (`fz_stext_block`) so inserted words reflow naturally without spilling across columns or margins.
  - **Image Replacement & Extraction**: Right-click embedded diagrams or photos to replace them with an updated graphic while preserving the original bounding box, or export the original lossless bitmap to disk.
- **Implementation Notes**:
  - Very high complexity; full text reflow across arbitrary subset fonts requires heavy synthesis and carries risk of altering strict technical layouts.

---

### 6. Side-by-Side Specification Revision Diffing [DEFERRED]
- **Description**: Visual and semantic comparison between two versions of a technical document (e.g., comparing RFC draft revisions or hardware spec v1.0 against v1.1).
- **Status Note**: Deferred per review due to pagination shift complexity in technical specifications and high engineering lift.
- **Capabilities**:
  - Visual Vector XOR Overlay: Highlights pixel and vector differences between corresponding pages using color coding (e.g. red for removed elements, green for added elements).
  - Synchronized Dual-Pane Text Diff: Side-by-side locked scrolling of matching sections with line-by-line diff highlighting.
  - Structural Revision Summary: High-level overview detailing which pages or sections experienced modifications, additions, or deletions.
- **Implementation Notes**:
  - Visual diff utilizes Fitz pixmap composition and blend modes; text diff runs on extracted `fz_stext_page` token streams.

---

## Architecture Decisions & Deprioritized Concepts

1. **In-Window Split View**:
   - *Status*: Deprioritized / Superseded.
   - *Rationale*: VectorPDF's multi-window child/parent architecture (`SnapshotWindowManager`) allows spawning auxiliary reading viewports for any link, anchor, selection, or page via Option-click or context menu. Combined with macOS native window tiling and Stage Manager, separate lightweight child windows provide greater flexibility across multiple monitors and display spaces with zero UI clutter or canvas view duplication.

2. **In-App Citation Popover Previews**:
   - *Status*: Superseded by Preferred Browser Link Resolution and Child Windows.
   - *Rationale*: Internal references (`[1]`, `[12]`) already support instant jumping and Option-click child window opening. External citations (DOIs, arXiv, publisher links) are routed to the user's preferred browser (configurable in Settings > General) to support authentication, BibTeX export, and full paper downloads without brittle web scraping.

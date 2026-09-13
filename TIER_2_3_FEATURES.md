# VectorPDF: Tier 2 & Tier 3 Features for Reconsideration

This document records prospective features identified during the competitive and architectural review of VectorPDF. These features are cataloged here for future prioritization and design.

---

## Tier 2 Features: Core Productivity & Document Ergonomics

### 1. Page Manipulation (Rotate, Reorder, Delete, Extract)
- **Description**: Allow the reader to alter the page layout of the PDF document directly.
- **Capabilities**:
  - Rotate current page or all pages 90° clockwise/counterclockwise (persisting to PDF `/Rotate` dictionary).
  - Drag-and-drop page reordering in the Thumbnail view.
  - Delete individual pages or page ranges.
  - Extract/Export selected pages or page ranges to a new standalone PDF file.
- **Implementation Notes**:
  - MuPDF Fitz provides `pdf_rotate_page`, `pdf_delete_page`, and `pdf_graft_page` for lossless page operations without re-rasterizing vector streams.

---

### 2. User Bookmarks (Independent of PDF Table of Contents)
- **Description**: Allow users to drop personal, named bookmarks at specific page locations.
- **Capabilities**:
  - Press `⌘D` or click a ribbon icon to add a bookmark with an optional custom label.
  - Sidebar section or menu listing all bookmarks for the current document.
  - Fast jumping with keyboard shortcuts (`⌃1` - `⌃9`).
- **Implementation Notes**:
  - Can be persisted in user preferences/local application support SQLite or saved into the PDF as private metadata or standard PDF bookmark outline items.

---

### 3. macOS Native Look Up & Speech (Text-to-Speech)
- **Description**: Integration with macOS linguistic and accessibility subsystems for highlighted/selected text.
- **Capabilities**:
  - Context menu item: **Look Up "..."** invoking native `NSDataDetector` / Quick Look Dictionary, Wikipedia, and Translation popover.
  - Speech menu item: **Start Speaking / Stop Speaking** using `NSSpeechSynthesizer` or `AVSpeechSynthesizer` on the selected text or from current page forward.

---

### 4. Interactive Form Flattening
- **Description**: Permanently bake filled AcroForm fields into the vector page graphics.
- **Capabilities**:
  - File > **Flatten Form Fields...** or Save As option.
  - Replaces interactive widget annotations with static appearance streams (`/AP`), preventing further accidental edits when emailing or submitting signed documents.
- **Implementation Notes**:
  - MuPDF Fitz has native `pdf_flatten_inheritable_page_items` and `pdf_drop_widgets` support.

---

### 5. Document Metadata & Font Inspector
- **Description**: Inspector panel detailing technical document parameters.
- **Capabilities**:
  - General info: Title, Author, Subject, Keywords, Producer, Creator, Creation Date, Modification Date, PDF version.
  - Security info: Encryption type, permissions (printing allowed, copying allowed, modifying allowed).
  - Font list: Embedded vs. system fonts, font format (Type 1, TrueType, OpenType, CIDFont), subsetting status.
  - Page metrics: TrimBox, MediaBox, CropBox, BleedBox.

---

## Tier 3 Features: Specialized & Advanced Research Workflows

### 1. SyncTeX Integration (LaTeX Pair-Reading)
- **Description**: Bidirectional synchronization between LaTeX source code (VS Code, MacTeX, Sublime, TeXShop) and VectorPDF.
- **Capabilities**:
  - **Direct synchronization**: `⌘-Click` on any word in the PDF sends the corresponding `.tex` file line and column to the editor via URL scheme or IPC (`subl`, `code`, `texshop://...`).
  - **Reverse synchronization**: Command line invocation `vectorpdf --synctex-forward line:col:file.tex target.pdf` jumps directly to and highlights the target point in the PDF.
- **Implementation Notes**:
  - Leverage `synctex_parser.c` (standard TeXLive C library).

---

### 2. In-Window Split View (Dual-Pane Reading)
- **Description**: Split the active window into two independent panes showing different pages or sections of the *same* document.
- **Capabilities**:
  - Horizontal or vertical split (`⌘\`).
  - Read an appendix or mathematical proof in one pane while tracking the main argument in the other.
  - Independent zoom and scroll positions with synchronized bookmarking/highlighting.

---

### 3. Academic Paper Intelligence & Reference Tooltips
- **Description**: Automatic detection and rich previews of academic citations and formulas.
- **Capabilities**:
  - Hovering over a reference citation (e.g. `[12]` or `(Vaswani et al., 2017)`) previews the bibliography entry in a lightweight popover without having to jump to the end of the document.
  - DOI / arXiv link resolver: Option to copy BibTeX entry or open publisher page directly.

---

### 4. Book Mode Cover Page Offset
- **Description**: Professional two-page spread formatting for bound books and magazines.
- **Capabilities**:
  - In Two-Page Mode, allow an option: "Show First Page Alone (Cover Page)".
  - Ensures left/right page symmetry aligns with recto/verso printing (odd pages on the right, even pages on the left).

---

### 5. Reading Themes & Contrast Customization
- **Description**: Custom visual presentation themes for long reading sessions.
- **Capabilities**:
  - Pre-calibrated palettes: Sepia (warm paper), Solarized Dark, Solarized Light, Pure Black (OLED / high contrast).
  - Inverted luminance with chromatic preservation (images and figures retain true color while text and backgrounds invert).


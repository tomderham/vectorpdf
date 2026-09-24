# VectorPDF: Tier 2 & Tier 3 Features for Reconsideration

This document records prospective features identified during the competitive and architectural review of VectorPDF. These features are cataloged here for future prioritization and design.

---

## Tier 2 Features: Core Productivity & Document Ergonomics

### 1. Page Manipulation & PDF Import [COMPLETED]
- **Description**: Alter page layout and assemble multi-document PDFs directly.
- **Capabilities**:
  - Rotate current page, selected pages, or all pages 90° CW/CCW/180° (persisting to PDF `/Rotate` dictionary).
  - Drag-and-drop page reordering in the Thumbnail view with live insertion indicator and count badges (single-page and multi-page bulk moves).
  - Duplicate individual pages or multiple selected pages (`⌘D` or context menu), inserting identical page copies directly adjacent to the selection with dirty tracking and temporary working copy.
  - Delete individual pages or bulk selected pages (safely preventing deletion of all pages).
  - Extract/Export selected pages or page ranges to a new standalone PDF file via save panel.
  - Insert pages from external PDF into opened documents via menu bar (File > **Insert Pages from PDF…** `⌥⌘I`), context menu, or **direct drag-and-drop from Finder** into the thumbnail grid at any drop insertion slot.
- **Implementation Status**: Completed via `MuPDFBridge` (`mupdf_pdf_rotate_page`, `mupdf_pdf_delete_pages`, `mupdf_pdf_reorder_pages`, `mupdf_pdf_duplicate_pages`, `mupdf_pdf_import_pages`, `mupdf_pdf_extract_pages`), `PDFDocumentCore`, `PDFViewerViewModel`, and `PDFThumbnailGridView`.

---

### 2. User Bookmarks & Anchors [COMPLETED]
- **Description**: Drop personal, named markers at specific page locations and spatial selections.
- **Capabilities**:
  - **Anchors Subsystem**: Supersedes simple page bookmarks by capturing exact target rects, section headings (matched deterministically from outline), and user notes.
  - **Quick Bookmark/Anchor**: Press `⌘B` or select **Anchors > Add Anchor** to bookmark the currently visible page and position instantly.
  - **Sidebar & Menu Navigation**: Dedicated Anchors tab (Tab 2 with custom vector anchor icon) and top-level **Anchors** menu bar listing all anchors for one-click jump with animated scrolling and visual flash highlight.
- **Implementation Status**: Completed via `SnapshotTarget`, `PDFViewerViewModel`, `PDFUI`, and `Anchors` menu bar.

---

### 3. Native Selection Look Up & Translation [COMPLETED]
- **Description**: Native macOS dictionary look up and on-device translation for highlighted/selected text.
- **Capabilities**:
  - Context menu item: **Look Up "..."** invoking macOS Dictionary Services.
  - Context menu item: **Translate "..."** invoking Apple's native system `Translation` framework (`translationPresentation` in macOS 15+ with fallback to web translation).
- **Implementation Status**: Completed via `PDFViewerViewModel.translateSelection` and `TranslationPresentationHelper`. (Note: Text-to-Speech demoted to Tier 3 Item 10).

---

### 4. Interactive Form Flattening
- **Description**: Permanently bake filled AcroForm fields into the vector page graphics.
- **Capabilities**:
  - File > **Flatten Form Fields...** or Save As option.
  - Replaces interactive widget annotations with static appearance streams (`/AP`), preventing further accidental edits when emailing or submitting signed documents.
- **Implementation Notes**:
  - MuPDF Fitz has native `pdf_flatten_inheritable_page_items` and `pdf_drop_widgets` support.

---

### 5. Document Metadata & Font Inspector [COMPLETED]
- **Description**: Inspector panel detailing technical document parameters, cryptographic security permissions, page geometry boxes, and embedded fonts.
- **Capabilities**:
  - **General Metadata**: Title, Author, Subject, Keywords, Producer, Creator, Creation Date, Modification Date, PDF version/format, File Size, Page Count.
  - **Security & Permissions**: Encryption status and algorithm; individual permission flags (printing allowed, high quality printing, copying allowed, modifying allowed, annotations allowed, form filling allowed, accessibility extraction allowed, page assembly allowed).
  - **Page Geometry**: Live dimensional breakdown of MediaBox, CropBox, BleedBox, TrimBox, and ArtBox per page with origin and width/height, switchable between Points (`pt`), Inches (`in`), and Millimeters (`mm`).
  - **Font Inspector**: Complete searchable catalog of document fonts, detailing PostScript name, clean family name, subtype (Type 1, TrueType, Type 0/CID, etc.), encoding, and badges for Embedded Subset (`ABCDEF+`), Fully Embedded, or System Fallback.
  - **macOS Native Access**: Standard `⌘I` shortcut, File > **Document Properties…**, and clean modal sheet without toolbar clutter.
- **Implementation Status**: Completed via `MuPDFBridge` (`mupdf_document_get_metadata`, `mupdf_document_get_permissions`, `mupdf_page_get_boxes`, `mupdf_document_get_fonts`), `PDFDocumentCore`, `PDFViewerViewModel`, and `PDFDocumentPropertiesView`.

---

### 6. True PDF Content Redaction & Security Scrubbing
- **Description**: Permanent removal of sensitive, proprietary, classified, or PII text and vector content from technical documents.
- **Capabilities**:
  - Search & Redact: Batch-redact all occurrences of a confidential string, API key, email address, or regex pattern across a multi-thousand-page document.
  - Rectangular Box Redaction: Blackout or whiteout of proprietary schematics, register tables, or author identities for double-blind review.
  - Permanent Stream Scrubbing: Unlike cosmetic overlay rectangles, underlying vector paths, text glyphs, and character quads are completely purged from the PDF stream so they cannot be extracted by scrapers or CLI tools.
  - Metadata Sanitization: One-click option to strip creator metadata, edit histories, embedded thumbnails, and XML attachments.
- **Implementation Notes**:
  - MuPDF Fitz provides native low-level redaction functions (`pdf_redact_page`, `pdf_clean_page`) that physically rewrite the content stream and rebuild the xref table.

---

### 7. On-Device OCR & Searchable Text Generation for Scanned Documents
- **Description**: Generate an invisible, searchable text layer for scanned technical datasheets, legacy patents, paper RFC archives, and legacy hardware manuals.
- **Capabilities**:
  - Auto-detection of image-only/raster pages lacking extractable text streams.
  - Local Apple Silicon Neural Engine OCR via Apple's Vision framework (`VNRecognizeTextRequest`).
  - Synthesizes an invisible structured text layer (`fz_stext_page`) aligned precisely with character bounding quads.
  - Enables VectorPDF's instant search, column-aware selection, and semantic indexer on scanned documents without sending data to cloud servers.
- **Implementation Notes**:
  - OCR results can be injected as an invisible text layer (PDF text rendering mode 3) or stored in an adjacent local cache file.

---

### 8. Technical Leader-Line Callout Annotations & Review Export
- **Description**: Precision engineering review annotations for schematics, architecture diagrams, and code snippets.
- **Capabilities**:
  - Two-Segment Leader Callouts: Text callout boxes with adjustable elbow lines and arrow pointers directing attention to specific circuit components, memory registers, or code lines.
  - Dimension Arrows: Double-headed measurement arrows with centered dimension text.
  - Review Summary Export: One-click export of all annotations, highlights, and comments into a structured Markdown review log, CSV issue table, or BibTeX notes file for Jira/GitHub ticketing.
- **Implementation Notes**:
  - Leverages standard PDF `/Callout` annotation dictionaries (`pdf_annot`) supported in Fitz.

---

### 9. Lossless Multi-Document Merging & PDF Import into Opened Documents
- **Description**: Assemble comprehensive specification packages by importing and combining independent PDFs directly into an already-opened document without losing vector fidelity or re-encoding.
- **Capabilities**:
  - **Import / Insert File into Opened PDF**: Menu item (File > **Insert Pages from PDF...**) or dragging a PDF file from Finder directly into the Thumbnail Grid at any designated drop insertion slot.
  - **Post-Import Manipulation**: All imported pages seamlessly become part of the active working copy, immediately eligible for thumbnail reordering, rotation, annotation, duplication, or deletion.
  - Append or insert pages from another PDF (e.g., attaching an errata sheet, schematic addendum, or appendix to an existing standard).
  - Batch merging of chapter PDFs into a unified manual.
  - Split multi-part specifications into standalone volumes.
- **Implementation Notes**:
  - MuPDF provides `pdf_graft_page` to copy page dictionaries and stream objects directly between documents without rasterization. Drop handling accepts `UTType.pdf` / file URLs in `ThumbnailPageDropDelegate`.

---

### 10. Native Text & Document Translation
- **Description**: Translation subsystem for foreign-language datasheets, patents, research papers, and international technical standards.
- **Capabilities**:
  - **Selection Translation (Native macOS Popover)**: Select any passage in the PDF and choose **Translate "..."** from the context menu or press a keyboard shortcut (`⌃⌥T`). Invokes macOS's native system translation UI (via Apple's `TranslationSession` / `translationPresentation` or `NSWorkspace`), supporting instant pronunciation, dictionary lookup, and language auto-detection.
  - **In-App On-Device Translation**: Utilizes Apple's native Translation framework (`import Translation` in macOS 15+ / Apple Foundation Models) for private, zero-latency on-device translation without sending document contents to third-party cloud servers.
  - **Full Document Translation (Dual-Pane / Export)**:
    - Extracts structured text blocks (`fz_stext_page`) across all pages.
    - Displays a synchronized dual-pane reading view with the original PDF in the primary pane and translated text paragraphs aligned side-by-side in the secondary pane.
    - Optional export to a translated PDF document or bilingual Markdown reference file.
- **Implementation Notes**:
  - Selection translation is readily achievable using macOS native popover presentation. Full document batch translation can run asynchronously via `PDFSearchActor`-like background actors and cached locally.

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

---

### 6. Engineering Blueprint Measurement & Scale Calibration
- **Description**: Precise distance, perimeter, and area measurement tools for architectural drawings, PCB layouts, and mechanical engineering schematics.
- **Capabilities**:
  - Scale Calibration: Calibrate drawing scale ratio (e.g. 1 in = 10 ft, 1 mm = 50 mm, or click two points of a known dimension to calibrate automatically).
  - Dimension Measurement: Measure linear distance between any two points with snapped perpendicular guidelines and dimension text overlays.
  - Perimeter & Area Calculation: Multi-point polygon tracing with live area and perimeter readouts.
  - Angle Measurement: Precise vertex angle inspector for mechanical and structural schematics.
- **Implementation Notes**:
  - Adheres to standard PDF `/Measure` and `/VP` (Viewport) dictionaries defined in ISO 32000.

---

### 7. Side-by-Side Specification Revision Diffing [DEFERRED]
- **Description**: Visual and semantic comparison between two versions of a technical document (e.g., comparing RFC draft revisions or hardware spec v1.0 against v1.1).
- **Status Note**: Deferred / abandoned for now per user review due to pagination shift complexity in technical specifications and high engineering lift.
- **Capabilities**:
  - Visual Vector XOR Overlay: Highlights pixel and vector differences between corresponding pages using color coding (e.g. red for removed elements, green for added elements).
  - Synchronized Dual-Pane Text Diff: Side-by-side locked scrolling of matching sections with line-by-line diff highlighting.
  - Structural Revision Summary: High-level overview detailing which pages or sections experienced modifications, additions, or deletions.
- **Implementation Notes**:
  - Visual diff utilizes Fitz pixmap composition and blend modes; text diff runs on extracted `fz_stext_page` token streams.

---

### 8. Direct PDF Content Editing (In-Place Text & Image Modification)
- **Description**: Direct editing of the underlying PDF content stream operators (`/Contents`) and embedded raster XObjects (`/XObject /Subtype /Image`), moving beyond overlay annotations to modify the document itself.
- **Capabilities**:
  - **In-Place Typo & Parameter Correction**: Click directly on existing text blocks to modify errata, fix typos, or update version strings, dates, and author metadata.
  - **Font Matching & Subset Handling**: Automatically detects font family, point size, and weight from the text block. For embedded font subsets that lack glyphs for new characters, seamlessly substitutes matching system fonts (SF Pro, Helvetica, New York, Courier) and embeds new `/Font` descriptors into page `/Resources`.
  - **Bounded Paragraph Reflow**: Recomputes line breaks within the structured text block boundary (`fz_stext_block`) so inserted words reflow naturally without spilling across columns or margins.
  - **Image Replacement & Extraction**: Right-click embedded diagrams or photos to replace them with an updated graphic (e.g. updated architecture block diagram or schematic) while preserving the original bounding box, or export the original lossless bitmap to disk.
- **Implementation Notes**:
### 9. macOS Speech & Accessibility (Text-to-Speech)
- **Description**: Text-to-speech audio reading for selected text or hands-free listening to technical specifications.
- **Capabilities**:
  - Context menu / shortcut: **Start Speaking / Stop Speaking** using `AVSpeechSynthesizer` or `NSSpeechSynthesizer`.
  - Sentence-level audio playback with configurable speech rate and voice selection.

---

## Feature Prioritization & Implementation Roadmap

To maintain VectorPDF's focus on professional readers navigating long, complex, and technical documents, features are prioritized into four sequential execution phases based on **User Impact for Technical Workflows**, **Implementation Complexity in MuPDF Fitz/Swift**, and **Competitive Differentiation against PDF Expert**.

### Phase 1: High-Impact Essentials
*Features addressing everyday navigation and basic document management gaps with low-to-moderate engineering friction.*

1. **User Bookmarks & Anchors (`⌘B`)** — *Tier 2, Item 2* **[COMPLETED]**
   - *Why*: Critical for bookmarking key chapters, registers, or proofs across 500+ page specs without modifying the author's outline.
   - *Status*: Complete. Unified into Anchors system with spatial bounding boxes, outline heading matching, dedicated sidebar tab, and `⌘B` quick anchor shortcut.
2. **Page Manipulation & PDF Import** — *Tier 2, Item 1* **[COMPLETED]**
   - *Why*: The #1 expected document ergonomics tool. Rotating landscape schematics, reordering pages, duplicating pages (`⌘D`), and importing external PDFs.
   - *Status*: Complete. Full multi-page rotation, bulk drag-and-drop reordering, duplication, deletion, extraction, and direct Finder PDF drag-and-drop import.
3. **Selection Translation & Look Up** — *Tier 2, Item 3* **[COMPLETED]**
   - *Why*: Immediate comprehension boost for engineers reading foreign patents, datasheets, or international standards.
   - *Status*: Complete. Native Apple `Translation` framework popover and Dictionary Services integration.
4. **Technical Leader-Line Callout Annotations & Review Export** — *Tier 2, Item 8*
   - *Why*: Directly serves engineering reviews (pointing to specific lines of code, diagram nodes, or register bits) with Markdown export for Jira/GitHub.
   - *Lift*: Moderate. Extends existing annotation subsystem with `/Callout` geometry.

---

### Phase 2: High-Value Technical Differentiators
*Capabilities that elevate VectorPDF's utility for dense technical specifications while remaining offline and private.*

5. **In-Window Split View (`⌘\`)** — *Tier 3, Item 2*
   - *Why*: Essential for technical reading—viewing an appendix, circuit schematic, or equation proof in one pane while tracking the narrative in the other.
   - *Lift*: Moderate. Two synchronized `PDFCanvasView` viewports over the existing shared core engine.
6. **On-Device Apple Vision OCR for Scanned Documents** — *Tier 2, Item 7*
   - *Why*: Eliminates the frustration of unsearchable scanned legacy manuals and patents, running 100% locally on Apple Silicon.
   - *Lift*: Moderate. `VNRecognizeTextRequest` pipeline generating structured text quads.
7. **True PDF Content Redaction & Security Scrubbing** — *Tier 2, Item 6*
   - *Why*: Vital for corporate, legal, defense, and academic peer review (double-blind submissions). MuPDF actually scrubs vector streams rather than drawing cosmetic masks.
   - *Lift*: Moderate. MuPDF `pdf_redact_page` and `pdf_clean_page`.
8. **Document Metadata & Font Inspector** — *Tier 2, Item 5*
   - *Why*: Immediate technical insight into PDF version, embedded font subsets, security permissions, and page geometry boxes.
   - *Lift*: Low. Direct Fitz document dictionary queries.
9. **Lossless Document Merging & Page Grafting** — *Tier 2, Item 9*
   - *Why*: Assembling master manuals by merging errata, addenda, and appendices.
   - *Lift*: Moderate. Fitz `pdf_graft_page`.

---

### Phase 3: Research & Technical Moats
*Advanced specialized capabilities that set VectorPDF apart from all mainstream PDF readers.*

10. **SyncTeX Integration (LaTeX Pair-Reading)** — *Tier 3, Item 1*
    - *Why*: Unbeatable moat for academic researchers, mathematicians, and engineers writing papers in LaTeX.
    - *Lift*: Moderate-to-High. C bridge to `synctex_parser.c` with URL schemes for VS Code/TeXShop.
11. **Academic Paper Intelligence & Citation Tooltips** — *Tier 3, Item 3*
    - *Why*: Hovering over `[12]` or `(Author, 2024)` previews the bibliography entry without losing reading position.
    - *Lift*: Moderate. Regex pattern matching over `StructuredTextModel` + floating popovers.
12. **Full Document Translation (Parallel View)** — *Tier 2, Item 10*
    - *Why*: Reading full foreign-language specifications side-by-side with synchronized translated text.
    - *Lift*: High. Batch translation actor + synchronized dual-pane scroll coordinator.
13. **Engineering Blueprint Measurement & Scale Calibration** — *Tier 3, Item 6*
    - *Why*: Essential for reading engineering drawings, PCB layouts, and architectural schematics.
    - *Lift*: Moderate-to-High. ISO 32000 `/Measure` dictionaries and snapped vector overlays.
14. **Side-by-Side Specification Revision Diffing** — *Tier 3, Item 7*
    - *Why*: Instantly spot what changed between spec v1.0 and v1.1 via visual XOR overlays and synchronized text diffs.
    - *Lift*: Moderate-to-High. Fitz pixmap blend modes + text alignment diff algorithms.

---

### Phase 4: Heavy Architectural & Specialized Investments
*High-effort features with specific architectural trade-offs or niche utility.*

15. **Direct PDF Content Editing (In-Place Text & Image Modification)** — *Tier 3, Item 8*
    - *Why*: PDF Expert's flagship marketing feature. Useful for minor typo/errata fixes, but full text reflow across arbitrary subset fonts requires heavy CoreText/Fitz synthesis and risks altering strict page layouts.
    - *Lift*: Very High. Substantive content stream rewriting and font descriptor synthesis.
16. **Interactive Form Flattening** — *Tier 2, Item 4*
    - *Why*: Baking form fields before submission. Useful, but specialized.
    - *Lift*: Low. Fitz `pdf_flatten_inheritable_page_items`.
17. **Book Mode Cover Page Offset & Contrast Themes** — *Tier 3, Items 4 & 5*
    - *Why*: Aesthetic polish for specific two-page book reading contexts.
    - *Lift*: Low-to-Moderate.





<!-- keywords: export, convert, plain text, text, Word, docx, SVG, image, images, picture, PNG, JPEG, JPG, TIFF, dpi, resolution, page as image, flatten, flattened, optimize, optimized, reduce file size, compress, smaller, downsample, images, fonts, subset, outlines, text to outlines, plotter, annotations summary, CSV, Markdown, searchable PDF, OCR, PDF -->

# Export to other formats

To export a whole document, choose File > Export Document As, then choose Plain Text, Word Document, Scalable Vector Graphics, Images, Flattened PDF, Optimized PDF or Searchable PDF. The annotations summary and measurements have their own commands.

## Plain text

Saves the document's text as a `.txt` file.

## Word document

Saves a `.docx` file you can edit in Word and other apps. Complex page layouts may look different from the PDF.

## SVG

Saves each page as a Scalable Vector Graphics file, with text as vector paths, so it looks exactly like the PDF. A multi-page document is saved as a folder with one file per page.

## Images

Saves pages as pictures, as they look in VectorPDF, with their comments and form fields and only the [layers](layers.md) shown. Choose File > Export Document As > Images. In the save dialog, choose:

- **Format:** PNG keeps every detail and suits drawings and text. JPEG makes smaller files and suits photos. TIFF is for apps that need it, such as some document and fax systems.
- **Resolution:** 72 dpi for the screen, 150 dpi for a document or presentation, 300 or 600 dpi for printing.
- **Pages:** all pages, the current page, or the pages selected in the [thumbnails](outline-and-thumbnails.md).

One page is saved as one file. Several pages are saved in a folder with the name you give, one image each, numbered by page. A very large page, such as a big drawing at 600 dpi, is made smaller so that its longest side is 16,384 pixels.

To export particular pages, select their thumbnails, right-click one, then choose Export Pages as Images.

## Flattened PDF

Saves a PDF with annotations and form fields made part of the page, so they can't be changed. In the save dialog, choose what to flatten:

- **Flatten annotations and markups**
- **Flatten form fields (make static)**

The flattened PDF has only what's on the [layers](layers.md) shown. Hidden layers are left out, with everything on them, annotations included. The layers left can still be shown and hidden, and annotations flattened onto the page stay on their layers.

> **Note:** Flattening doesn't remove what's underneath. To remove content, use [redaction](redact.md).

## Optimized PDF

Saves a smaller copy of the PDF, including any changes you haven't saved. The document you have open doesn't change. Data the document no longer uses is removed, duplicates are merged and everything is compressed. In the save dialog, you can also choose:

- **Keep only the characters each font uses:** removes the parts of embedded fonts the document doesn't use. On by default.
- **Images:** keep them as they are, or reduce them to 300 dpi (for printing) or 150 dpi (for reading on screen). Only images sharper than that are reduced. Photos are saved as JPEG; diagrams and screenshots stay lossless. Black-and-white scans are left alone.
- **Convert text to outlines:** draws every letter as a shape, so the document looks the same on plotters, cutters and print systems that don't have its fonts. Text in the copy can't be selected, searched or copied.

How much smaller the copy is depends on the document. Scans and photos shrink the most when you reduce their images.

## Searchable PDF

Saves a copy of a scanned PDF, including any changes you haven't saved, with the text recognized on its scanned pages saved in it as an invisible layer, so other apps can search, select and copy it. It's available for documents with scanned pages. See [Save the recognized text in the PDF](scanned-pages.md#save-the-recognized-text-in-the-pdf).

## Annotations summary

Choose File > Export Annotations Summary (⇧⌘E) to save a list of the document's annotations, including ones from other apps, with their authors, statuses and replies. By default it's a Markdown file. Give the file a `.csv` extension to save a spreadsheet instead.

## Measurements

To export measurements, use the [Takeoff table](takeoff.md).

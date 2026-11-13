<!-- keywords: OCR, scan, scanned, scans, text recognition, recognize text, image, Run OCR, select, copy, highlight, searchable PDF, save text, text layer, language -->

# Search and select text on scanned pages

A scanned page is a picture of text. VectorPDF can recognize the text using optical character recognition (OCR), on your Mac, so you can search it, select it and mark it up.

## How it works

When you open a document, VectorPDF looks for scanned pages among the first 50 pages and recognizes the text on them in the background. When there's more to do, the Search tab shows how many scanned pages it found.

- **To recognize all the scanned pages it has found,** click **Run OCR** in the Search tab.
- A search also recognizes them, so you can just start searching.

Highlights follow the text, even if the page was scanned at a slight angle.

Text is recognized in the languages in your Mac's Language & Region settings that recognition supports, or in English if it supports none of them.

## Select recognized text

Once a page has been recognized, you can [select and copy](select-text.md) its text and [highlight, underline or strike through](text-markup.md) it as you would on any other page. Recognition can take a moment, and pages after the first 50 need Run OCR or a search first.

Recognition can make mistakes, so check anything you copy that has to be exact. Selections start and end cleanly at the edges of words. Within a word, their ends are approximate.

> **Note:** Recognized text is used while the document is open, and isn't saved in the PDF unless you choose to save it (see below). Markups you add are saved. If you redact or rotate a page, its text is recognized again.

## Save the recognized text in the PDF

To make a scanned PDF searchable in other apps too, such as Preview, Spotlight and Acrobat, save the recognized text in it. The text is added as an invisible layer under each scanned page, where it was recognized, so the pages look the same.

- **To save it in the document,** choose File > Save with Recognized Text, or click **Save in PDF** in the Search tab once its text is recognized. Your other changes are saved too.
- **To save it in a copy,** choose File > Export Document As > Searchable PDF. The document you have open doesn't change.

Either way, VectorPDF first recognizes any scanned pages it hasn't yet, showing its progress. This takes a moment for each page. You can click Cancel, and nothing is saved.

Only pages with no text of their own get text. Once the text is in the file, those pages are no longer treated as scanned: VectorPDF selects and searches the saved text, as other apps do.

> **Important:** Recognition can make mistakes, and saved text goes wherever the file goes: into search indexes, copied text and screen readers. Check that the text is right before you rely on it, or save a copy instead. Saving the document also opens it again from the file, so you can't undo changes made before the save.

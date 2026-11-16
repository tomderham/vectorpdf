<!-- keywords: save, save as, unsaved, revert, revert to saved, reload, discard, undo all, share, Show in Finder, changes, autosave, recover, recovery, crash, quit unexpectedly, PDF -->

# Save your changes

Markups, form entries, page changes and redactions aren't written to your file until you save. A window with unsaved changes shows a dot in its close button.

| To | Do this |
| --- | --- |
| Save | Choose File > Save, or press ⌘S |
| Save a copy under a new name | Choose File > Save As, or press ⇧⌘S |
| Save a password-protected copy | Choose File > [Save Encrypted with Password](passwords.md), or press ⌥⌘S |

If you close a document with unsaved changes, VectorPDF asks whether to save them.

## Discard your changes

To throw away everything since you last saved, choose File > Revert to Saved. VectorPDF asks first, then opens the file as it was last saved, on the page you were reading. You can't undo a revert.

To make a smaller copy of a document, see [Optimized PDF](export.md#optimized-pdf).

## If VectorPDF quits unexpectedly

While a document has unsaved changes, VectorPDF keeps a copy of it on your Mac, updated about every 30 seconds. If VectorPDF quits unexpectedly, it offers the copies the next time it opens:

- **Open Recovered Copy** saves each copy beside its original, named "(Recovered)", and opens it. The original isn't changed. Compare them, then keep the one you want.
- **Decide Later** keeps the copies and asks again next time.
- **Discard Changes** deletes the copies.

The copy is deleted when you save, revert or close the document without saving, and when you quit VectorPDF. Password-protected documents aren't copied, because the copy wouldn't be encrypted.

## Share a document

Choose File > Share to use a macOS sharing service, or File > Show in Finder (⇧⌘R) to find the file. On the Start screen, right-click a document to show it in the Finder.

## What isn't saved in the PDF

Some things stay with VectorPDF and don't travel with the file: [anchors](anchors.md), your [reading position](reading-positions.md), the view rotation, and text from [OCR](scanned-pages.md), unless you [save it in the PDF](scanned-pages.md#save-the-recognized-text-in-the-pdf).

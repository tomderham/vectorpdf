# Troubleshooting

## I can't select text, follow links or use markup tools

Check that the view isn't rotated or in Two-Page Mode. These work only in Single Page view with no rotation. See [Zoom, rotate and page layout](zoom-and-layout.md).

Also check that a Markup or Measurement tool isn't active. Press Escape to return to selecting text.

## A search finds nothing

- The pages may be scanned. See [Search scanned pages with OCR](scanned-pages.md).
- Check that Match Case and Whole Word are turned off in the [search options](search.md#search-options), and that Smart Search is on.
- If markers interrupt the text, add an [ignored pattern](search.md#ignore-clutter-in-the-text).

## Holding ⌘ doesn't show a preview

Link Peek works on links in the document, and on web links to documents open in another tab. Plain-text references aren't links, so right-click them instead. See [References across documents](cross-document-references.md).

The VectorPDF window also needs to be the active window.

## A reference to another document isn't found

Open the other document as a tab in the same window. Separate windows aren't searched.

## A cloud document won't open

Check your connection, and that the file downloads in the Finder, then try again.

## The Agent is unavailable or shows only passages

The Agent needs macOS 26 or later, and writing answers on-device needs Apple Intelligence to be turned on and ready. If indexing fails, click Retry in the Agent tab. See [Choose how the Agent answers](agent-engines.md).

## An online model isn't answering

Check the API key and model in [Settings](settings.md), and that your account with the service has credit. VectorPDF answers on-device if the service fails.

## My changes disappeared

Changes need to be [saved](save.md). If another app changed the file while you had unsaved changes, choosing Reload from Disk discards them.

## Help doesn't show this guide

Tips can only show this guide when VectorPDF is in your Applications folder. Move it there, then choose Help > VectorPDF Help again.

## Get more help

Report a problem or ask a question on [GitHub](https://github.com/tomderham/vectorpdf/issues). A sample PDF helps, if you can share one.

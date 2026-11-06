<!-- keywords: search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, recent searches, search history, section, outline, table of contents, PDF -->

# Search a document

## Find text

1. Press ⌘F. VectorPDF shows the Search tab in the sidebar.
2. Type what you're looking for. Results appear as they're found, starting from the page you're on.

Results are listed by page, each with the text around it, and every match is highlighted in the document. In a document with an [outline](outline-and-thumbnails.md), results are also grouped by the section they're in. The section's name stays at the top of the list while you scroll through its results. To see which larger sections it's part of, hold the pointer over it.

## Move between results

| To | Do this |
| --- | --- |
| Go to the next result | Press Return or ⌘G, or click the down arrow |
| Go to the previous result | Press ⇧Return or ⇧⌘G, or click the up arrow |
| Go to any result | Click it |
| Step through the list | Click a result, then press the arrow keys |

Right-click a result to [create an anchor](anchors.md) from it, or to open it in a new window.

## Search again for something you searched before

Each document remembers the last 10 searches you went to a result for. To search for one again:

- Click the magnifying glass in the search field and choose it, or
- With the search field empty, click it in the Recent Searches list below the field.

VectorPDF goes to the nearest result. To forget a document's searches, choose Clear Recent Searches from the magnifying glass, or click Clear above the list. Applying redactions to a document also clears its recent searches.

## Search options

Click the options button beside the search field:

- **Match Case:** finds only text with the same capitalization.
- **Whole Word:** doesn't match inside longer words.
- **Smart Search:** this is on unless you turn it off. Spaces, hyphens, dashes and line breaks match each other, so “end-to-end” also finds “end to end”, even across a line break. Straight and curly quotes match each other too.

## Ignore clutter in the text

Some documents put markers in the middle of sentences, such as citation numbers, which stops a phrase from being found. Smart Search can look past them.

1. Choose VectorPDF > Settings.
2. Next to Ignored Search Patterns, click Edit.
3. Add one of the ready-made patterns, or your own regular expression, and turn it on.

The ready-made patterns cover numeric citations like [12], trademark symbols, star paging like *123, and IEEE 802.11 comment tags.

## Scanned documents

Scanned pages have no text to search until they've been recognized. See [Search and select text on scanned pages](scanned-pages.md).

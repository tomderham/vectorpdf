<!-- keywords: search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, PDF -->

# Search a document

## Find text

1. Press ⌘F. VectorPDF shows the Search tab in the sidebar.
2. Type what you're looking for. Results appear as they're found, starting from the page you're on.

Each result shows its page and the text around it, and every match is highlighted in the document.

## Move between results

| To | Do this |
| --- | --- |
| Go to the next result | Press Return or ⌘G, or click the down arrow |
| Go to the previous result | Press ⇧Return or ⇧⌘G, or click the up arrow |
| Go to any result | Click it |
| Step through the list | Click a result, then press the arrow keys |

Right-click a result to [create an anchor](anchors.md) from it, or to open it in a new window.

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

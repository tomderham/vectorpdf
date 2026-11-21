<!-- keywords: search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, recent searches, search history, section, outline, table of contents, right side, beside the outline, move search, PDF -->

# Search a document

## Find text

1. Press ⌘F. VectorPDF shows the Search tab in the sidebar, or on the right of the window if you've [moved it there](#see-results-beside-the-outline).
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

## See results beside the outline

To see the results and the outline at the same time, click the options button beside the search field and choose Show Search on Right. Search moves to the right side of the window and the sidebar shows the outline, or the page thumbnails if the document has no outline. Each outline entry with results shows how many it has, and the count for the section with the current result is highlighted. A section with its subsections hidden counts the results in them too. Click an outline entry and the results list scrolls to that section's results (or its subsections', if it has none of its own), while the page shows the section's heading; the current result stays where it was until you click one.

Each document remembers which side you put Search on. To put it back in the sidebar, choose Show Search on Right again to turn it off. To hide it while it's on the right, click the close button (×) beside it. To show it again, press ⌘F or click the Search button at the top of the sidebar.

Search shares the right side with the [Inspector](rulers-and-inspector.md#the-inspector). When both are open, switch between them with the Search and Inspector buttons at the top.

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
- **Show Search on Right:** moves Search out of the sidebar to the right of the window, so you can see it [beside the outline](#see-results-beside-the-outline).

## Ignore clutter in the text

Some documents put markers in the middle of sentences, such as citation numbers, which stops a phrase from being found. Smart Search can look past them.

1. Choose VectorPDF > Settings, then click Advanced.
2. Next to Ignored Search Patterns, click Edit.
3. Add one of the ready-made patterns, or your own regular expression, and turn it on.

The ready-made patterns cover numeric citations like [12], trademark symbols, star paging like *123, and IEEE 802.11 comment tags.

## Scanned documents

Scanned pages have no text to search until they've been recognized. See [Search and select text on scanned pages](scanned-pages.md).

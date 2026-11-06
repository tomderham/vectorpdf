<!-- keywords: compare, comparison, diff, difference, differences, revision, revisions, redline, changes, versions, side by side, synchronized scrolling, scroll together, renumbering, page numbers, cross-references, table of contents -->

# Compare two documents

Compare Documents shows two versions of a document side by side, with the text that changed highlighted in both. As you scroll, the other version scrolls to the same text, even where pages were added or removed between the versions.

## Open a comparison

1. Choose File > Compare Documents.
2. Choose the Original and the Revised document. Each menu lists the documents you have open, or choose Choose File to pick another. The document in front starts as the Original. Click Swap to exchange them.
3. Click Compare.

You can also right-click the document's title, or an empty part of the toolbar, and choose a document from Compare With. That compares the document in front with the one you choose.

The comparison opens in a new tab, with the original on the left and the revision on the right. Both are read-only there. To edit one, open it in its own tab.

## Read the changes

- Words removed from the original are highlighted in red, on the left.
- Words added in the revision are highlighted in green, on the right.
- Where text was added on one side only, a thin bar on the other side marks where it would be.
- Text that's the same in both but in another place is underlined in blue on both sides, such as a table that falls on the other side of a page break, or a clause that was moved. It takes ten words or more in a row to count. Moved text isn't counted as a change; the top of the Changes tab says how many passages are in another place.

The Changes tab in the sidebar lists every change: removed words struck through in red, added words in green, and the revision's page number. Click a change to go to it in both documents.

To step through the changes, click the up or down arrow at the top of the Changes tab, choose Go > Previous Change or Go > Next Change, or press ⌥⌘Up Arrow or ⌥⌘Down Arrow. The tab shows which change you're on, such as 3 of 12. That change is highlighted more strongly, and selected in the list.

Only the text is compared. Changes to formatting, images or drawings aren't shown. Running headers, footers and page numbers are left out, so they don't show up as changes when pages move.

## Find a section or a word

The sidebar's Outline & Thumbnails and Search tabs work on the revision, as they do in any tab. Go to a section, or to a search result, and the original follows to the same text.

## Scroll and zoom together

The line about a third of the way down each side shows the same text. When one side has text the other doesn't, the other side waits until you've scrolled past it. You can scroll either side; the other follows.

Zooming one side zooms both, and keeps the text you're reading where it is. Zoomed in past the width of the page, scrolling one side across scrolls the other across too, so both show the same part of the page.

## Comparison options

At the top of the Changes tab, choose Ignore Case or Ignore Punctuation to leave out differences in capitalization or punctuation. Curly and straight quotation marks, and the different kinds of dash, always count as the same.

### Ignore renumbering

When a clause, figure or table is added or removed, everything after it is numbered again, and every page number after it moves. In a long document, most of the changes can be new numbers in the table of contents, the list of figures and the cross-references. Ignore Renumbering, which is on to begin with, leaves those out:

- An entry in the table of contents or a list of figures, or a cross-reference such as "see 9.4.2.18", doesn't count as changed when it links to the same place in both versions, even though its number or page number is new.
- At the place it links to, the heading's or caption's own number doesn't count as changed either, when it changed the same way. For example, "Figure 9-806" becoming "Figure 9-809".

What counts as the same place comes from the documents' links, not from what the numbers look like. A cross-reference that now links somewhere else still shows as a change, and so does a number that isn't part of a link, such as "Table 9-12" typed as plain text. A heading that was reworded still shows as changed at the heading itself, even where its entry in the table of contents doesn't.

Ignore Renumbering needs documents with links inside them, which most word processors and publishing apps make for the contents and cross-references. It isn't available when neither document has any. A PDF saved again by an app that drops links has none, even if the original did.

To see every number that changed, turn off Ignore Renumbering.

## If the comparison isn't useful

- **A document has no text to compare:** scanned pages have no text until they're recognized. See [Search and select text on scanned pages](scanned-pages.md).
- **These documents have little text in common:** they may not be versions of the same document.

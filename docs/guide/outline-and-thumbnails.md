<!-- keywords: outline, table of contents, TOC, contents, bookmarks, bookmark, add bookmark, edit outline, build outline, headings, generate table of contents, rename, indent, outdent, thumbnail, thumbnails, sidebar -->

# Outline and thumbnails

Click the Outline & Thumbnails tab at the top of the sidebar, then choose **Outline** or **Thumbnails**.

## Outline

The outline is the document's table of contents, if it has one. The section you're reading is highlighted as you scroll. After you go to a search result or follow a link, the section it's in is highlighted, until you scroll again.

- **Go to a section:** click it. Its heading is scrolled to near the top of the window, or left where it is if you can already see it.
- **Show or hide subsections:** click the arrow next to a section.
- **Find a section:** type in the “Search outline” field. Only matching sections are shown.
- **See where search results are:** with Search [on the right of the window](search.md#see-results-beside-the-outline), each section shows how many results it has.
- **Keep a section handy:** right-click it to create an [anchor](anchors.md), or to open it in a new window.

## Edit the outline

You can add entries to a document's outline (other apps may call them bookmarks), and rename, move and delete them. The changes become part of the file when you [save](save.md).

To add an entry, go to the place it should lead to, then choose Edit > Add Outline Entry (⌥⌘B). If you've selected text, the entry leads to the text and is offered as its title. Otherwise it leads to the top of the page you're reading. Type a title, then click **Add**. Entries added this way go among the top entries in page order, so this is also how to start an outline for a document that has none.

Right-click an entry for the rest:

| To | Choose |
| --- | --- |
| Add an entry after this one, or inside it | Add Entry After, or Add Entry Inside |
| Rename it | Rename |
| Make it lead to the selected text, or the page you're reading | Go Here Instead |
| Move it among the entries at its level | Move Up or Move Down |
| Put it inside the entry above it, or take it out of the one it's in | Indent or Outdent |
| Delete it, with the entries inside it | Delete Entry |

You can also drag an entry to move it, or drop it on another entry to put it inside. The entries inside it move with it. While the outline is filtered by the “Search outline” field, entries can't be moved, so Move Up, Move Down, Indent and Outdent aren't on the menu and entries can't be dragged; the other commands work. Edit > Undo (⌘Z) takes back changes to the outline, one at a time.

### Build an outline from headings

Choose Edit > Build Outline from Headings to make an outline of the document's headings. It's also on the right-click menu of an outline entry. A list of the headings found opens first: uncheck any that aren't headings, click a title to change it, and use the indent buttons to move a heading up or down a level. Click the arrow beside a heading to see it on the page. Then click **Create Outline**, or **Replace Outline** if the document has one; Edit > Undo brings the old outline back.

In a tagged PDF, the headings are those its tags mark. In other PDFs, VectorPDF looks for lines set apart from the body text: larger, or bold where the text isn't. A larger style is a higher level than a smaller one, and section numbers such as 3.2.1 give the levels within one style. Running headers and footers, figure and table captions and the lines of a table of contents are left out.

A document's styles don't always say which lines are headings, so check the list. Headings in scanned pages aren't found, even once their text is recognized. In some tagged PDFs, section numbers are drawn so that they aren't part of the text, and the entries come without them.

## Thumbnails

Thumbnails show every page. Click one to go to that page.

Hold ⌘ to select several pages, or ⇧ to select a range. Then drag them to a new position, or right-click to rotate, duplicate, extract or delete them. See [Rearrange pages](pages.md).

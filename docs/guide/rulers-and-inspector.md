<!-- keywords: status bar, pointer position, coordinates, page size, paper size, A4, Letter, ARCH, rulers, guides, grid, snap, units, millimeters, inches, points, Inspector, font, font size, color, image resolution, dpi, ppi, line width, navigator, pan and zoom, word count, character count -->

# Rulers, the status bar and the Inspector

These show where things are on a page and what they're made of. They're off until you turn them on in the View menu, so reading stays uncluttered.

## The status bar

Choose View > Show Status Bar (⌘/) to show a strip under the page. It shows:

- **Where the pointer is** on the page, from the page's top-left corner. On a page with a [drawing scale](drawing-scale.md), it also shows that place in real-world units.
- **The size of the page** under the pointer, or of the current page, with the paper size when it matches one: A0 to A6, B3 to B5, Letter, Legal, Tabloid, ANSI C to E and ARCH A to E. Drawing sets often mix sheet sizes, so this changes as you move between pages.
- **A measurement as you draw it:** its length, its angle and how far it runs across (ΔX) and down (ΔY); a perimeter's length so far and its last segment; an area so far and its perimeter. See [Measure lengths, areas and angles](measure.md).
- **The size of the text selection,** in words and characters.

Choose the units, Millimeters, Inches or Points, from the menu at the right of the status bar. The rulers, grid and Inspector use them too.

## Rulers and guides

Choose View > Rulers and Grid > Show Rulers (⌘R) to show rulers along the top and left of the page. They measure the page under the pointer from its top-left corner, and a line on each ruler shows where the pointer is.

| To | Do this |
| --- | --- |
| Add a guide | Drag from a ruler onto the page |
| Move a guide | Drag it |
| Remove a guide | Drag it off the page |
| Remove every guide | Choose View > Rulers and Grid > Clear Guides |

Guides belong to the page you put them on. They stay while the document is open, and aren't saved in it.

## The grid

Choose View > Rulers and Grid > Show Grid (⌘') to draw a grid on every page, from its top-left corner. Choose its spacing from View > Rulers and Grid > Grid Spacing. Every fifth line is darker.

When **Snap to Guides and Grid** is on in View > Rulers and Grid, the points of a measurement snap to guides near the pointer, and to the grid while it shows, as they snap to corners with Vertex Magnetic Snapping.

## The Inspector

Choose View > Show Inspector (⌃⌘I) to show the Inspector beside the page. You can also right-click the page and choose Inspect.

- **Text, images and drawings:** with the Inspector open, click the page in Select mode. The Inspector shows what's drawn there, and the page outlines it:
  - **Text:** the font, its size, the character, its color and color space, and whether the font is in the file. A font that isn't is drawn with a substitute, which may not look the same when printed.
  - **Images:** their size in pixels, their resolution as placed on the page, their size on the page, color space and bits per component. Check an image's resolution before printing or optimizing.
  - **Drawings:** a line's width and color, or a shape's fill color.
- **Annotations:** select an annotation to see its type, author, dates, layer, opacity and color. To move it, type its position (**X** and **Y**, from the page's top-left corner) and press Return. Rectangles, ovals, text boxes, callouts, stamps and revision clouds can also be resized: type their **Width** and **Height**.

## The navigator

Choose View > Show Navigator (⌃⌘N) to show a miniature of the page in view, in the corner of the window. The part on screen is outlined. Drag the outline, or click the miniature, to move around a large sheet while zoomed in.

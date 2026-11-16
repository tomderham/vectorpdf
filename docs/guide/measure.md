<!-- keywords: measure, measurement, measurements, length, distance, dimension, perimeter, area, angle, count, counting, tally, symbols, ortho, snap, snapping, edit, change, move, reshape, handle, offset -->

# Measure lengths, areas and angles, and count

Press ⇧⌘M to show the Measurement toolbar. If your drawing is to scale, [set the scale](drawing-scale.md) first.

Zoom in for accuracy before you measure. Pressing Escape cancels a measurement in progress. Press Escape again, or click the selected tool, to put the tool down.

## Measurement tools

| Tool | How to use it |
| --- | --- |
| Linear Dimension | Drag from one point to the other. |
| Perimeter | Click each point along the path. Press Return or double-click to finish. |
| Polygon Area | Click each corner. Press Return, double-click, or click the first point to close the shape. |
| Vertex Angle | Click a point on the first line, then the corner, then a point on the second line. |
| Count | Type what you're counting in the group box, such as Outlets, then click each one. |

## Count things on a drawing

Choose the Count tool, then type a group name in the box beside it, such as Outlets or Type A Doors, or choose one already in the document from the menu next to the box. Each click places a marker, a dot in the Measurement toolbar's color, and the toolbar shows how many of that group are on the page. Change the group name to count something else; each group is counted apart. Use a different color for each group to tell them apart on the page.

To move a marker, drag it with the Select tool. To remove one, right-click it and choose Delete Count Marker. The [takeoff table](takeoff.md) shows how many of each group there are on each page, with totals. Markers are saved in the PDF as small circles, so other apps show them too.

## Draw accurately

- **Ortho Lock** keeps lines at 0°, 45° and 90°. Hold ⇧ to switch it for one line: to measure at any angle while it's on, or to keep a line straight while it's off.
- **Vertex Magnetic Snapping** snaps the pointer to corners and endpoints in the drawing.
- **Guides and the grid:** with View > Rulers and Grid > Snap to Guides and Grid on, points snap to guides you've dragged out from the rulers, and to the grid while it shows. See [Rulers, the status bar and the Inspector](rulers-and-inspector.md).
- **The status bar** (View > Show Status Bar) shows more of a measurement as you draw it than its label: its angle and how far it runs across and down, or an area's perimeter so far.

## Change a measurement

Choose **Select**, the arrow at the start of the Measurement toolbar, or press Escape to put the measuring tool down. Point at a measurement and a dashed outline shows it; click it to select it. ⇧-click to select several, or hold ⌥ and drag across them. With a measuring tool in use, clicking measures again instead.

A selected measurement has handles on its points.

| To | Do this |
| --- | --- |
| Move one point | Drag its handle. Ortho Lock and snapping work as they do when you measure. |
| Move the whole measurement | Drag its line, or press the arrow keys (⇧ moves it 10 points). |
| Move a dimension line nearer or further from what it measures | Drag its label, or drag the dimension line once it's away from the points. |
| Change its color | Choose a color with the color button in the Measurement toolbar. |
| Change its line width | Choose or type a width in the Measurement toolbar's line width box. |

The value is worked out again as you drag. Drag past the edge of the window to scroll, for a measurement longer than the view. Choose Edit > Undo to put a measurement back as it was. Measurements already saved in the PDF can be changed too.

To select an area, click its edge: clicking inside it selects the text there.

## Change how measurements look

Use the color button and line width box in the Measurement toolbar before you measure. Choose a width in points, or type one, from 0.1 to 72 points. New measurements are gray, 1.5 points wide, until you choose otherwise. VectorPDF remembers what you choose, and the Markup toolbar keeps its own colors and widths. To change the color or width of a measurement you've already made, select it, then choose a color or width in the Measurement toolbar. The width is saved in the PDF.

## Keep or remove measurements

Measurements are annotations, stored in the PDF when you [save](save.md). To delete one, right-click it, then choose the delete command, such as Delete Dimension, Delete Area Takeoff or Delete Count Marker.

To list all your measurements, see the [Takeoff table](takeoff.md).

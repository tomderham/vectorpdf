<!-- keywords: layers, layer, optional content, OCG, CAD, drawings, AutoCAD, Revit, show, hide, visibility, markups, annotations, new layer -->

# Show and hide layers

Drawings exported from CAD and design programs often keep each part of a sheet on its own layer: walls, electrical, plumbing, dimensions, revision clouds. You can show or hide each one.

The Layers tab appears at the top of the sidebar only when the document has layers.

- **Show or hide a layer:** click its checkbox. The page redraws straight away.
- **Choose one of a group:** some documents group layers so only one shows at a time, such as a sheet's languages or scales. These have round buttons; choosing one hides the others.
- **Headings** group the layers listed under them. They can't be hidden themselves.
- **Locked layers** have a lock next to them. The document doesn't let them be shown or hidden.

Layers you hide are also left out when you [print](print.md), [select text](select-text.md) or [search](search.md), so you only work with what you can see.

## Put annotations on a layer

In a document with layers, annotations can go on a layer too, so they're shown and hidden with it. Other apps that read layers, such as Acrobat and Bluebeam, show and hide them the same way.

- **Choose where new annotations go:** in the [Markup toolbar](draw-and-notes.md) or the [Measurement toolbar](measure.md), click the layer menu (it says **No Layer** until you choose one) and choose a layer. Everything you make from then on goes on it, until you choose another layer or **No Layer**. You can also choose it under **New annotations** in the Layers tab, or right-click a layer there and choose **Put New Annotations Here**. The layer new annotations go on has a pencil next to it.
- **Move an annotation to another layer:** right-click it and choose **Layer**, then a layer, or **None** to take it off any.
- **Add a layer of your own:** click **+** at the top of the Layers tab, or choose **New Layer…** from the layer menu, then name it. New annotations go on it. The new layer is saved with the document.

The layer menu appears only when a document has layers, so the toolbars of other documents are unchanged.

Annotations on a hidden layer disappear from the page, the [Comments tab](draw-and-notes.md#see-all-annotations) and the [Takeoff table](takeoff.md), and can't be selected or erased. The Annotations table still lists them, with their layer.

If you choose a hidden layer for new annotations, it's shown, so what you make doesn't disappear. Undo puts an annotation back on the layer it was on.

## What's saved

Which layers are shown isn't saved with the document. The next time you open it, its layers are shown as the document itself sets them, and anyone you send it to sees the same.

> **Note:** A single-page document opens with the sidebar hidden. Use the sidebar button in the toolbar to show it.

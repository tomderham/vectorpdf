<!-- keywords: Statusleiste, Zeigerposition, Koordinaten, Seitengröße, Papierformat, Lineale, Hilfslinien, Raster, einrasten, Einheiten, Millimeter, Zoll, Punkt, Inspector, Schrift, Schriftgröße, Farbe, Bildauflösung, Navigator, Wortanzahl, Zeichenanzahl, status bar, pointer position, coordinates, page size, paper size, A4, Letter, ARCH, rulers, guides, grid, snap, units, millimeters, inches, points, font, font size, color, image resolution, dpi, ppi, line width, navigator, pan and zoom, word count, character count -->
<!-- source: a8ac6b2f855f -->

# Lineale, Statusleiste und Inspector

Diese zeigen, wo sich etwas auf einer Seite befindet und woraus es besteht. Sie sind ausgeschaltet, bis du sie im Menü „View“ einschaltest, damit das Lesen übersichtlich bleibt.

## Die Statusleiste

Wähle View > Show Status Bar (⌘/), um unter der Seite eine Leiste einzublenden. Sie zeigt:

- **Wo der Zeiger ist**, gemessen von der linken oberen Ecke der Seite. Auf einer Seite mit [Zeichnungsmaßstab](drawing-scale.md) zeigt sie diese Stelle auch in realen Einheiten.
- **Die Größe der Seite** unter dem Zeiger oder der aktuellen Seite, mit dem Papierformat, wenn sie einem entspricht: A0 bis A6, B3 bis B5, Letter, Legal, Tabloid, ANSI C bis E und ARCH A bis E. Plansätze mischen oft Blattgrößen, daher ändert sich die Anzeige, wenn du zwischen Seiten wechselst.
- **Eine Messung beim Zeichnen:** ihre Länge, ihren Winkel und wie weit sie nach rechts (ΔX) und nach unten (ΔY) reicht; die bisherige Länge eines Umfangs und sein letztes Segment; eine bisherige Fläche und ihren Umfang. Siehe [Längen, Flächen und Winkel messen](measure.md).
- **Die Größe der Textauswahl** in Wörtern und Zeichen.

Wähle die Einheiten, Millimeters, Inches oder Points, im Menü rechts in der Statusleiste. Lineale, Raster und Inspector verwenden sie ebenfalls.

## Lineale und Hilfslinien

Wähle View > Rulers and Grid > Show Rulers (⌘R), um Lineale oben und links an der Seite einzublenden. Sie messen die Seite unter dem Zeiger von ihrer linken oberen Ecke aus, und eine Linie auf jedem Lineal zeigt, wo der Zeiger ist.

| Aktion | Vorgehen |
| --- | --- |
| Eine Hilfslinie hinzufügen | Ziehe von einem Lineal auf die Seite |
| Eine Hilfslinie bewegen | Ziehe sie |
| Eine Hilfslinie entfernen | Ziehe sie von der Seite |
| Alle Hilfslinien entfernen | Wähle View > Rulers and Grid > Clear Guides |

Hilfslinien gehören zu der Seite, auf die du sie gesetzt hast. Sie bleiben erhalten, solange das Dokument geöffnet ist, und werden nicht darin gesichert.

## Das Raster

Wähle View > Rulers and Grid > Show Grid (⌘'), um auf jeder Seite ein Raster von ihrer linken oberen Ecke aus zu zeichnen. Seinen Abstand wählst du unter View > Rulers and Grid > Grid Spacing. Jede fünfte Linie ist dunkler.

Wenn **Snap to Guides and Grid** unter View > Rulers and Grid eingeschaltet ist, rasten die Punkte einer Messung an Hilfslinien in der Nähe des Zeigers ein und am Raster, solange es eingeblendet ist, so wie sie mit „Vertex Magnetic Snapping“ an Ecken einrasten.

## Der Inspector {#the-inspector}

Wähle View > Show Inspector (⌃⌘I), um den Inspector neben der Seite einzublenden. Du kannst auch mit der rechten Maustaste auf die Seite klicken und „Inspect“ wählen.

- **Text, Bilder und Zeichnungen:** Klicke bei geöffnetem Inspector im Modus „Select“ auf die Seite. Der Inspector zeigt, was dort gezeichnet ist, und die Seite umrandet es:
  - **Text:** die Schrift, ihre Größe, das Zeichen, seine Farbe und seinen Farbraum und ob die Schrift in der Datei enthalten ist. Eine Schrift, die fehlt, wird durch eine Ersatzschrift dargestellt, die gedruckt anders aussehen kann.
  - **Bilder:** ihre Größe in Pixeln, ihre Auflösung, wie sie auf der Seite platziert sind, ihre Größe auf der Seite, ihren Farbraum und die Bits pro Komponente. Prüfe die Auflösung eines Bilds vor dem Drucken oder Optimieren.
  - **Zeichnungen:** die Breite und Farbe einer Linie oder die Füllfarbe einer Form.
- **Anmerkungen:** Wähle eine Anmerkung aus, um ihren Typ, Autor, ihre Daten, Ebene, Deckkraft und Farbe zu sehen. Um sie zu bewegen, gib ihre Position ein (**X** und **Y**, von der linken oberen Ecke der Seite aus) und drücke den Zeilenschalter. Rechtecke, Ovale, Textfelder, Legenden, Stempel und Revisionswolken lassen sich auch in der Größe ändern: Gib ihre **Width** und **Height** ein.

## Der Navigator

Wähle View > Show Navigator (⌃⌘N), um in der Ecke des Fensters eine Miniatur der angezeigten Seite einzublenden. Der Teil auf dem Bildschirm ist umrandet. Ziehe die Umrandung oder klicke auf die Miniatur, um dich bei starkem Zoom auf einem großen Blatt zu bewegen.

<!-- keywords: Rechteck, Kreis, Radius, Durchmesser, Bogen, Bogenlänge, messen, Messung, Messungen, Länge, Abstand, Maß, Umfang, Fläche, Winkel, Einrasten, measure, measurement, measurements, length, distance, dimension, perimeter, area, angle, ortho, snap, snapping, bearbeiten, ändern, verschieben, Ziehpunkt, Versatz, edit, change, move, reshape, handle, offset, zählen, Zählung, Strichliste, Symbole, count, counting, tally, symbols, rectangle, circle, radius, diameter, arc, arc length, curve -->
<!-- source: fea799877718 -->

# Längen, Flächen und Winkel messen und zählen

Drücke ⇧⌘M, um die Symbolleiste „Measurement“ einzublenden. Wenn deine Zeichnung maßstabsgetreu ist, [lege zuerst den Maßstab fest](drawing-scale.md).

Zoome für mehr Genauigkeit in die Zeichnung, bevor du misst. Mit der Escape-Taste brichst du eine laufende Messung ab. Drücke sie noch einmal oder klicke auf das ausgewählte Werkzeug, um das Werkzeug wegzulegen.

## Messwerkzeuge

| Werkzeug | Verwendung |
| --- | --- |
| Linear Dimension | Ziehe von einem Punkt zum anderen. |
| Perimeter | Klicke auf jeden Punkt entlang des Pfads. Drücke zum Abschließen die Return-Taste oder doppelklicke. |
| Polygon Area | Klicke auf jede Ecke. Drücke die Return-Taste, doppelklicke oder klicke auf den ersten Punkt, um die Form zu schließen. |
| Rectangle Area | Ziehe von einer Ecke zur gegenüberliegenden. |
| Circle | Ziehe von der Mitte zum Rand. Das Etikett zeigt die Fläche und den Durchmesser, und die [Statusleiste](rulers-and-inspector.md) zeigt auch Radius und Umfang. |
| Arc Length | Klicke auf den Anfang des Bogens, auf einen Punkt darauf und dann auf sein Ende. Das Etikett zeigt die Länge entlang des Bogens und seinen Radius. |
| Vertex Angle | Klicke auf einen Punkt der ersten Linie, dann auf die Ecke und dann auf einen Punkt der zweiten Linie. |
| Count | Gib im Gruppenfeld ein, was du zählst, etwa Steckdosen, und klicke dann auf jedes Exemplar. |

## Dinge auf einer Zeichnung zählen {#count-things-on-a-drawing}

Wähle das Werkzeug „Count“ und gib im Feld daneben einen Gruppennamen ein, etwa Steckdosen oder Türen Typ A, oder wähle im Menü neben dem Feld eine Gruppe, die es im Dokument schon gibt. Jeder Klick setzt eine Markierung, einen Punkt in der Farbe der Symbolleiste „Measurement“, und die Symbolleiste zeigt, wie viele dieser Gruppe auf der Seite sind. Ändere den Gruppennamen, um etwas anderes zu zählen; jede Gruppe wird für sich gezählt. Verwende für jede Gruppe eine andere Farbe, um sie auf der Seite zu unterscheiden.

Um eine Markierung zu bewegen, ziehe sie mit dem Werkzeug „Select“. Um eine zu entfernen, klicke mit der rechten Maustaste darauf und wähle „Delete Count Marker“. Die [Takeoff-Tabelle](takeoff.md) zeigt, wie viele jeder Gruppe auf jeder Seite sind, mit Summen. Markierungen werden im PDF als kleine Kreise gesichert, sodass andere Apps sie ebenfalls zeigen.

## Genau zeichnen

- **Ortho Lock** hält Linien bei 0°, 45° und 90°. Halte ⇧ gedrückt, um es für eine Linie umzuschalten: So misst du bei eingeschaltetem „Ortho Lock“ in jedem Winkel oder hältst bei ausgeschaltetem eine Linie gerade.
- **Vertex Magnetic Snapping** lässt den Zeiger an Ecken und Endpunkten in der Zeichnung einrasten.
- **Hilfslinien und Raster:** Wenn View > Rulers and Grid > Snap to Guides and Grid eingeschaltet ist, rasten Punkte an Hilfslinien ein, die du aus den Linealen gezogen hast, und am Raster, solange es eingeblendet ist. Siehe [Lineale, Statusleiste und Inspector](rulers-and-inspector.md).
- **Die Statusleiste** (View > Show Status Bar) zeigt beim Zeichnen mehr von einer Messung als ihre Beschriftung: ihren Winkel und wie weit sie nach rechts und nach unten reicht, oder den bisherigen Umfang einer Fläche.

## Eine Messung ändern

Wähle **Select**, den Pfeil am Anfang der Symbolleiste „Measurement“, oder drücke die Escape-Taste, um das Messwerkzeug wegzulegen. Zeige auf eine Messung, und ein gestrichelter Umriss zeigt sie; klicke darauf, um sie auszuwählen. Klicke bei gedrückter ⇧-Taste, um mehrere auszuwählen, oder ziehe bei gedrückter ⌥-Taste über sie. Solange ein Messwerkzeug aktiv ist, misst ein Klick stattdessen erneut.

Eine ausgewählte Messung hat Ziehpunkte an ihren Punkten.

| Aktion | Vorgehensweise |
| --- | --- |
| Einen Punkt verschieben | Ziehe seinen Ziehpunkt. „Ortho Lock“ und das Einrasten wirken wie beim Messen. |
| Die ganze Messung verschieben | Ziehe ihre Linie oder drücke die Pfeiltasten (mit ⇧ um 10 Punkte). |
| Eine Maßlinie näher an das Gemessene oder weiter davon weg rücken | Ziehe ihre Beschriftung oder, sobald sie von den Punkten abgerückt ist, die Maßlinie selbst. |
| Ihre Farbe ändern | Wähle mit der Farbtaste in der Symbolleiste „Measurement“ eine Farbe. |
| Linienstärke ändern | Wähle eine Stärke im Feld für die Linienstärke in der Symbolleiste „Measurement“ oder gib eine ein. |

Der Wert wird beim Ziehen neu berechnet. Ziehe über den Fensterrand hinaus, um zu scrollen, wenn eine Messung länger als die Ansicht ist. Wähle Edit > Undo, um eine Messung wieder so herzustellen, wie sie war. Auch Messungen, die bereits im PDF gesichert sind, lassen sich ändern.

Um eine Fläche auszuwählen, klicke auf ihren Rand: Ein Klick in die Fläche wählt den Text dort aus.

Ein Rechteck, Kreis oder Bogen behält seine Form, wenn du ihn änderst: Ziehe eine Ecke des Rechtecks, die Mitte oder den Rand des Kreises oder einen der drei Punkte des Bogens. Sie werden als Fläche oder Länge entlang ihres Umrisses gesichert, sodass andere Apps, die PDF-Messungen lesen, sie ebenfalls als Messungen zeigen, mit eigenen Werten für den Umriss (bei Kreis und Bogen bis auf 0,05 % die von VectorPDF).

## Das Aussehen von Messungen ändern

Verwende vor dem Messen die Farbtaste und das Feld für die Linienstärke in der Symbolleiste „Measurement“. Wähle eine Stärke in Punkt oder gib eine ein, von 0,1 bis 72 Punkt. Neue Messungen sind grau und 1,5 Punkt stark, bis du etwas anderes wählst. VectorPDF merkt sich deine Wahl, und die Symbolleiste „Markup“ behält ihre eigenen Farben und Stärken. Um die Farbe oder Stärke einer bereits erstellten Messung zu ändern, wähle sie aus und wähle dann in der Symbolleiste „Measurement“ eine Farbe oder Stärke. Die Stärke wird im PDF gesichert.

## Messungen behalten oder entfernen

Messungen sind Anmerkungen, die im PDF gespeichert werden, wenn du [sicherst](save.md). Um eine zu löschen, klicke mit der rechten Maustaste darauf und wähle den Befehl zum Löschen, etwa Delete Dimension, Delete Area Takeoff, Delete Circle Measurement oder Delete Count Marker.

Eine Liste aller deiner Messungen findest du in der [Takeoff-Tabelle](takeoff.md).

<!-- keywords: Ebenen, Ebene, optionaler Inhalt, CAD, Zeichnungen, einblenden, ausblenden, Sichtbarkeit, Markierungen, Anmerkungen, neue Ebene, Ebene umbenennen, Ebene löschen, Ebenenkonfiguration, Konfigurationen, Ebenenzustände, Plotten, layers, layer, optional content, OCG, AutoCAD, Revit, show, hide, visibility, markups, annotations, new layer, rename layer, delete layer, layer configuration, configurations, layer states, plot -->
<!-- source: 4525c1273cca -->

# Ebenen ein- und ausblenden

Zeichnungen, die aus CAD- und Designprogrammen exportiert werden, legen oft jeden Teil eines Blatts auf eine eigene Ebene: Wände, Elektro, Sanitär, Bemaßungen, Revisionswolken. Du kannst jede davon ein- oder ausblenden.

Der Tab „Layers“ erscheint oben in der Seitenleiste nur, wenn das Dokument Ebenen hat. Wie ein Dokument seine erste Ebene bekommt, erfährst du unter [Ebenen hinzufügen, umbenennen und löschen](#add-rename-and-delete-layers).

- **Eine Ebene ein- oder ausblenden:** Klicke auf ihr Markierungsfeld. Die Seite wird sofort neu gezeichnet.
- **Eine aus einer Gruppe wählen:** Manche Dokumente gruppieren Ebenen so, dass nur eine gleichzeitig angezeigt wird, etwa die Sprachen oder Maßstäbe eines Blatts. Diese haben runde Tasten; wählst du eine, werden die anderen ausgeblendet.
- **Überschriften:** Sie fassen die darunter aufgeführten Ebenen zusammen und können selbst nicht ausgeblendet werden.
- **Gesperrte Ebenen:** Sie haben ein Schloss daneben. Das Dokument lässt nicht zu, dass sie ein- oder ausgeblendet werden.

Ausgeblendete Ebenen werden auch beim [Drucken](print.md), beim [Auswählen von Text](select-text.md) bei der [Suche](search.md), beim [Exportieren eines reduzierten PDF](export.md#flattened-pdf) und bei [Fragen an den Agent](agent.md) weggelassen. So arbeitest du nur mit dem, was du siehst.

## Eine Ebenenkonfiguration auswählen

Manche Dokumente bieten mehr als eine Art, ihre Ebenen anzuzeigen, etwa eine zum Plotten, eine für jedes Gewerk oder eine für jede Sprache. Bei diesen zeigt der Tab „Layers“ oben statt der Anzahl der Ebenen die verwendete Konfiguration an. Sie heißt **Default**, bis du eine andere auswählst, außer das Dokument gibt seiner Standardkonfiguration einen Namen.

Klicke darauf und wähle eine Konfiguration aus. Ihre Ebenen werden so ein- und ausgeblendet und so aufgelistet, wie sie es festlegt.

Wenn du danach eine Ebene ein- oder ausblendest, erscheint **(Changed)** hinter dem Namen der Konfiguration. Wähle die Konfiguration erneut aus, um ihre Ebenen wiederherzustellen.

## Anmerkungen auf eine Ebene legen {#put-annotations-on-a-layer}

Auch Anmerkungen können auf einer Ebene liegen. Sie werden dann mit ihr ein- und ausgeblendet. Andere Apps, die Ebenen lesen, etwa Acrobat und Bluebeam, blenden sie genauso ein und aus.

- **Festlegen, wohin neue Anmerkungen kommen:** Klicke in der [Symbolleiste „Markup“](draw-and-notes.md) oder der [Symbolleiste „Measurement“](measure.md) auf das Ebenenmenü (es zeigt **No Layer**, bis du eine Ebene wählst) und wähle eine Ebene. Alles, was du danach erstellst, kommt auf diese Ebene, bis du eine andere Ebene oder **No Layer** wählst. Du kannst auch im Tab „Layers“ mit der rechten Maustaste auf eine Ebene klicken und **Put New Annotations Here** wählen. Neben der Ebene für neue Anmerkungen steht ein Stift.
- **Eine Anmerkung auf eine andere Ebene verschieben:** Klicke mit der rechten Maustaste darauf und wähle **Layer** und dann eine Ebene, oder **None**, um sie von jeder Ebene zu nehmen.
- **Eine eigene Ebene hinzufügen:** Siehe [Ebenen hinzufügen, umbenennen und löschen](#add-rename-and-delete-layers).

Das Ebenenmenü erscheint nur, wenn ein Dokument Ebenen hat. Die Symbolleisten anderer Dokumente bleiben also unverändert.

Anmerkungen auf einer ausgeblendeten Ebene verschwinden von der Seite, aus dem [Tab „Comments“](draw-and-notes.md#see-all-annotations) und aus der [Takeoff-Tabelle](takeoff.md) und lassen sich weder auswählen noch radieren. Die Tabelle „Annotations“ führt sie weiterhin auf, mit ihrer Ebene.

Wählst du eine ausgeblendete Ebene für neue Anmerkungen, wird sie eingeblendet, damit das, was du erstellst, nicht verschwindet. „Undo“ legt eine Anmerkung wieder auf die Ebene, auf der sie war.

## Ebenen hinzufügen, umbenennen und löschen {#add-rename-and-delete-layers}

Prüfende legen ihre Markierungen oft auf eigene Ebenen, etwa eine pro Gewerk oder Prüfrunde, auch auf Zeichnungen, die ohne Ebenen gekommen sind. Jeder dieser Befehle ändert das Dokument, und „Undo“ macht ihn rückgängig.

- **Eine Ebene hinzufügen:** Wähle Edit > New Layer… und gib ihr einen Namen. Das funktioniert in jedem PDF; so bekommt ein Dokument seine erste Ebene, und danach erscheinen der Tab „Layers“ und die Ebenenmenüs. Neue Anmerkungen kommen auf die neue Ebene. In einem Dokument, das schon Ebenen hat, kannst du auch oben im Tab „Layers“ auf **+** klicken oder im Ebenenmenü **New Layer…** wählen.
- **Eine Ebene umbenennen:** Wähle Edit > Rename Layer…, wähle die Ebene und gib ihren neuen Namen ein.
- **Eine Ebene löschen:** Wähle Edit > Delete Layer… und dann die Ebene. Ihre Anmerkungen bleiben auf der Seite, auf keiner Ebene. Nur Ebenen, die ausschließlich Anmerkungen enthalten, lassen sich löschen: Würde eine Ebene gelöscht, auf der die Zeichnung selbst liegt, bliebe dieser Teil der Zeichnung immer sichtbar. Solche Ebenen werden daher nicht aufgeführt.

## Was gesichert wird {#whats-saved}

Ebenen, die du hinzufügst, umbenennst oder löschst, werden mit dem Dokument gesichert, ebenso die Ebenen, auf denen Anmerkungen liegen.

Welche Ebenen angezeigt werden und welche Konfiguration du ausgewählt hast, wird nicht mit dem Dokument gesichert. Beim nächsten Öffnen werden seine Ebenen so angezeigt, wie das Dokument selbst es festlegt, und alle, denen du es sendest, sehen dasselbe.

> **Hinweis:** Ein Dokument mit einer oder zwei Seiten und Ebenen wird mit dem Tab „Layers“ geöffnet, außer du hast die Seitenleiste dafür ausgeblendet. Verwende die Seitenleistentaste in der Symbolleiste, um sie einzublenden.

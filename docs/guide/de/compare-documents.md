<!-- keywords: vergleichen, Vergleich, Unterschiede, Revision, Fassung, Version, Änderungen, nebeneinander, gemeinsam scrollen, Neunummerierung, Seitenzahlen, Querverweise, Inhaltsverzeichnis, compare, comparison, diff, difference, differences, revision, revisions, redline, changes, versions, side by side, synchronized scrolling, scroll together, renumbering, page numbers, cross-references, table of contents -->
<!-- source: 84d22a753af8 -->

# Zwei Dokumente vergleichen

Compare Documents zeigt zwei Fassungen eines Dokuments nebeneinander, wobei der geänderte Text in beiden hervorgehoben ist. Wenn du scrollst, scrollt die andere Fassung zum selben Text, auch wenn zwischen den Fassungen Seiten hinzugefügt oder entfernt wurden.

## Einen Vergleich öffnen

1. Wähle File > Compare Documents.
2. Wähle das Original („Original“) und die überarbeitete Fassung („Revised“). Jedes Menü listet die geöffneten Dokumente auf; wähle „Choose File“, um ein anderes auszuwählen. Das Dokument im Vordergrund ist zunächst das Original. Klicke auf „Swap“, um die beiden zu tauschen.
3. Klicke auf „Compare“.

Du kannst auch mit der rechten Maustaste auf den Titel des Dokuments oder auf einen leeren Bereich der Symbolleiste klicken und unter „Compare With“ ein Dokument wählen. Dann wird das Dokument im Vordergrund mit dem gewählten verglichen.

Der Vergleich wird in einem neuen Tab geöffnet, mit dem Original links und der überarbeiteten Fassung rechts. Beide sind dort schreibgeschützt. Um eines zu bearbeiten, öffne es in einem eigenen Tab.

## Die Änderungen lesen

- Aus dem Original entfernte Wörter sind links rot hervorgehoben.
- In der überarbeiteten Fassung hinzugefügte Wörter sind rechts grün hervorgehoben.
- Wo nur auf einer Seite Text hinzugefügt wurde, markiert ein schmaler Balken auf der anderen Seite die Stelle, an der er stünde.
- Text, der in beiden gleich ist, aber an einer anderen Stelle steht, ist auf beiden Seiten blau unterstrichen, etwa eine Tabelle, die auf die andere Seite eines Seitenumbruchs fällt, oder ein verschobener Abschnitt. Dafür braucht es mindestens zehn Wörter am Stück. Verschobener Text zählt nicht als Änderung; oben im Tab „Changes“ steht, wie viele Passagen an einer anderen Stelle stehen.

Der Tab „Changes“ in der Seitenleiste listet jede Änderung auf: entfernte Wörter rot durchgestrichen, hinzugefügte Wörter grün, dazu die Seitenzahl in der überarbeiteten Fassung. Klicke auf eine Änderung, um in beiden Dokumenten zu ihr zu gehen.

Um die Änderungen nacheinander durchzugehen, klicke oben im Tab „Changes“ auf den Auf- oder Abwärtspfeil, wähle Go > Previous Change oder Go > Next Change, oder drücke ⌥⌘Up Arrow oder ⌥⌘Down Arrow. Der Tab zeigt an, bei welcher Änderung du bist, zum Beispiel 3 of 12. Diese Änderung ist stärker hervorgehoben und in der Liste ausgewählt.

Verglichen wird nur der Text. Änderungen an Formatierung, Bildern oder Zeichnungen werden nicht angezeigt. Kopf- und Fußzeilen und Seitenzahlen werden ausgelassen, damit sie nicht als Änderungen erscheinen, wenn sich Seiten verschieben.

## Einen Abschnitt oder ein Wort finden

Die Tabs „Outline & Thumbnails“ und „Search“ in der Seitenleiste beziehen sich auf die überarbeitete Fassung, wie in jedem Tab. Gehe zu einem Abschnitt oder einem Suchergebnis, und das Original folgt zum selben Text.

## Gemeinsam scrollen und zoomen

Die Zeile etwa ein Drittel von oben zeigt auf beiden Seiten denselben Text. Hat eine Seite Text, den die andere nicht hat, wartet die andere, bis du daran vorbeigescrollt hast. Du kannst auf beiden Seiten scrollen; die andere folgt.

Wenn du eine Seite zoomst, werden beide gezoomt, und der Text, den du gerade liest, bleibt an seiner Stelle. Ist die Seite breiter als der Bereich, scrollt das seitliche Scrollen auf einer Seite auch die andere, sodass beide denselben Teil der Seite zeigen.

## Vergleichsoptionen

Wähle oben im Tab „Changes“ „Ignore Case“ oder „Ignore Punctuation“, um Unterschiede in Groß- und Kleinschreibung oder Zeichensetzung auszulassen. Typografische und gerade Anführungszeichen sowie die verschiedenen Arten von Strichen gelten immer als gleich.

### Neunummerierung ignorieren

Wird ein Abschnitt, eine Abbildung oder eine Tabelle hinzugefügt oder entfernt, wird alles danach neu nummeriert, und jede Seitenzahl danach verschiebt sich. In einem langen Dokument können die meisten Änderungen neue Nummern im Inhaltsverzeichnis, im Abbildungsverzeichnis und in den Querverweisen sein. „Ignore Renumbering“ ist von Anfang an eingeschaltet und lässt sie aus:

- Ein Eintrag im Inhaltsverzeichnis oder in einem Abbildungsverzeichnis oder ein Querverweis wie „siehe 9.4.2.18“ gilt nicht als geändert, wenn er in beiden Fassungen auf dieselbe Stelle verweist, auch wenn seine Nummer oder Seitenzahl neu ist.
- An der Stelle, auf die er verweist, gilt auch die eigene Nummer der Überschrift oder Bildunterschrift nicht als geändert, wenn sie sich auf dieselbe Weise geändert hat. Zum Beispiel wird aus „Figure 9-806“ „Figure 9-809“.

Was als dieselbe Stelle gilt, ergibt sich aus den Links der Dokumente, nicht daraus, wie die Nummern aussehen. Ein Querverweis, der jetzt woandershin verweist, wird weiterhin als Änderung angezeigt, ebenso eine Nummer, die nicht Teil eines Links ist, etwa „Table 9-12“ als einfacher Text. Eine umformulierte Überschrift wird an der Überschrift selbst weiterhin als geändert angezeigt, auch wo ihr Eintrag im Inhaltsverzeichnis es nicht wird.

„Ignore Renumbering“ braucht Dokumente mit Links darin, die die meisten Textverarbeitungs- und Publishing-Apps für Inhaltsverzeichnis und Querverweise erstellen. Hat keines der Dokumente welche, ist die Option nicht verfügbar. Ein PDF, das von einer App erneut gesichert wurde, die Links verwirft, hat keine, auch wenn das Original welche hatte.

Um jede geänderte Nummer zu sehen, schalte „Ignore Renumbering“ aus.

## Wenn der Vergleich nicht hilft

- **Ein Dokument hat keinen Text zum Vergleichen:** Gescannte Seiten haben erst Text, wenn er erkannt wurde. Siehe [Text auf gescannten Seiten suchen und auswählen](scanned-pages.md).
- **Diese Dokumente haben wenig Text gemeinsam:** Vielleicht sind es keine Fassungen desselben Dokuments.

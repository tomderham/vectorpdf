<!-- keywords: Logo, Bildwasserzeichen, mehrere Dateien, Chinesisch, Hindi, Arabisch, Kopfzeile, Kopfzeilen, Fußzeile, Fußzeilen, Seitenzahlen, Seitennummerierung, Bates, Bates-Nummern, Bates-Nummerierung, Wasserzeichen, ENTWURF, VERTRAULICH, juristisch, header, headers, footer, footers, page numbers, page numbering, Bates numbers, Bates numbering, watermark, watermarks, DRAFT, CONFIDENTIAL, stamp text, legal, discovery, PDF, Chinese, Japanese, Korean, Arabic, any language, logo, picture watermark, image watermark -->
<!-- source: 05436b7b8113 -->

# Kopfzeilen, Fußzeilen, Bates-Nummern und Wasserzeichen

Du kannst Text oben und unten auf Seiten setzen, etwa einen Titel, Seitenzahlen oder Bates-Nummern, und ein Wasserzeichen wie ENTWURF oder VERTRAULICH quer darüber. Wähle Edit > Headers, Footers and Watermark, fülle die gewünschten Teile aus und klicke dann auf **Add**. Eine Vorschau neben den Einstellungen zeigt die Seite, die du liest, so, wie sie aussehen wird, mit ihren eigenen Seiten- und Bates-Nummern; mit den Pfeilen darunter siehst du andere Seiten.

VectorPDF behält im Dokument, was du gewählt hast, sodass du Kopfzeilen, Fußzeilen und Wasserzeichen später ändern oder entfernen kannst. Wähle erneut Edit > Headers, Footers and Watermark, nimm deine Änderungen vor und klicke dann auf **Update**. Um alle zu entfernen, klicke auf **Remove All**.

Die Änderungen werden Teil der Datei, wenn du [sicherst](save.md).

## Kopf- und Fußzeile

Schreibe in eines der sechs Felder: links, mittig und rechts in der Kopfzeile und in der Fußzeile. Lass ein Feld leer, um dort nichts zu setzen.

Um eine Seitenzahl oder einen anderen Wert einzufügen, der sich von Seite zu Seite ändert, klicke in ein Feld und wähle dann aus dem Menü **Insert**:

| Insert | Zeigt |
| --- | --- |
| Page Number | Die Nummer der Seite, gezählt ab der ersten markierten Seite. Siehe [Seiten und Nummern](#pages-and-numbers). |
| Page Count | Wie viele Seiten das Dokument hat |
| Bates Number | Die Bates-Nummer der Seite |
| Date | Das heutige Datum |
| File Name | Den Dateinamen des Dokuments |

Jedes erscheint im Feld als Wort in doppelten spitzen Klammern, etwa `<<page>>`. Schreibe zum Beispiel `Seite `, füge Page Number ein, schreibe ` von ` und füge dann Page Count ein, um „Seite 3 von 12“ zu erhalten.

Du kannst Schrift, Größe und Farbe des Textes wählen sowie die Ränder: wie weit die Kopfzeile vom oberen Rand der Seite entfernt ist, die Fußzeile vom unteren und beide von den Seitenrändern, in Punkt (72 Punkt sind ein Zoll).

Text kann in jeder Sprache sein, etwa Chinesisch, Hindi oder Arabisch. Wo die gewählte Schrift die Zeichen nicht hat, wird eine Schrift auf deinem Mac verwendet, die sie hat, und die verwendeten Zeichen werden im Dokument gesichert, sodass es überall gleich aussieht.

## Wasserzeichen

Ein Wasserzeichen ist Text oder ein Bild. Für Text gib ihn ein; drücke den Zeilenschalter für eine zweite Zeile. Für ein Bild, etwa ein Logo, wähle **Picture**, klicke auf **Choose Picture** und lege dann seine Breite als Anteil der Seitenbreite fest. Wähle dann:

- **Font** und **Color**.
- **As large as fits the page** oder eine eigene Größe.
- **Opacity:** wie stark es sichtbar ist. Ein helles Wasserzeichen lässt die Seite lesbar.
- **Angle:** waagerecht, diagonal oder senkrecht.
- **Behind the page's content:** zeichnet das Wasserzeichen unter den Text und die Bilder der Seite statt darüber. Eine Seite mit Hintergrund, etwa eine gescannte Seite, verdeckt ein Wasserzeichen dahinter.

## Seiten und Nummern {#pages-and-numbers}

- **Pages:** alle Seiten, ungerade oder gerade Seiten und von einer Seite bis zu einer anderen. Lass From oder To leer für die erste oder letzte Seite.
- **First page marked is page:** die Nummer, die Page Number der ersten markierten Seite gibt. Die Nummern steigen mit jeder markierten Seite um eins.
- **Bates numbers:** ein Präfix, etwa ein Fall- oder Firmenname, die Anzahl der Stellen, die Startnummer und ein Suffix. Bates-Nummern steigen mit jeder markierten Seite um eins und werden mit Nullen aufgefüllt, etwa ACME-000001. Füge Bates Number in eine Kopf- oder Fußzeile ein, um sie anzuzeigen.

## Mehrere Dateien markieren

Um eine Reihe von Dokumenten für ein Verfahren zu nummerieren, mit Bates-Nummern, die von einer Datei zur nächsten weiterlaufen, richte die Markierungen ein und klicke dann auf **Apply to Other Files**. Wähle die PDFs und dann einen Ordner für die markierten Kopien; die Dateien selbst werden nicht geändert. Sie werden in der Reihenfolge ihrer Namen markiert, benenne sie also in der Reihenfolge, in der sie nummeriert werden sollen. Danach sagt VectorPDF, welche Bates-Nummern verwendet wurden, und listet jede Datei auf, die es nicht markieren konnte, etwa eine, die ein Passwort braucht.

## Gut zu wissen

- Kopfzeilen, Fußzeilen und Wasserzeichen sind Teil der Seite, keine [Anmerkungen](draw-and-notes.md), daher werden sie gedruckt und erscheinen auch in anderen Apps. Sie sind als Seitenschmuck gekennzeichnet, den Bildschirmleser überspringen können. Ihren Text kannst du durchsuchen und auswählen.
- Die Ränder werden an der Seite gemessen, wie sie angezeigt wird, sodass bei einer gedrehten Seite die Kopfzeile trotzdem oben steht.
- Kopfzeilen, Fußzeilen und Wasserzeichen, die andere Apps wie Adobe Acrobat hinzugefügt haben, lassen sich ebenfalls entfernen, wenn die App sie als solche gekennzeichnet hat (die meisten tun das): Findet VectorPDF welche, erscheint unter „Pages & Numbers“ **Remove them**, und die Vorschau zeigt die Seite ohne sie. Einmal entfernt, kommen sie nur zurück, wenn du zum gesicherten Dokument zurückkehrst.
- Wenn du sie zu einem [digital signierten](digital-signatures.md) Dokument hinzufügst, änderst du, was signiert wurde, daher werden seine Signaturen ungültig.

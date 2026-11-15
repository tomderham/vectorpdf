<!-- keywords: OCR, Scan, gescannt, Scans, Texterkennung, Text erkennen, Bild, auswählen, kopieren, hervorheben, scan, scanned, scans, text recognition, recognize text, image, Run OCR, select, copy, highlight, durchsuchbares PDF, Text sichern, Textebene, Sprache, searchable PDF, save text, text layer, language -->
<!-- source: 8b77a345a44e -->

# Text auf gescannten Seiten suchen und auswählen

Eine gescannte Seite ist ein Bild von Text. VectorPDF kann den Text mit optischer Zeichenerkennung (OCR) auf deinem Mac erkennen, sodass du ihn durchsuchen, auswählen und markieren kannst.

## So funktioniert es

Wenn du ein Dokument öffnest, sucht VectorPDF unter den ersten 50 Seiten nach gescannten Seiten und erkennt ihren Text im Hintergrund. Wenn noch mehr zu tun ist, zeigt der Tab „Search“ an, wie viele gescannte Seiten gefunden wurden.

- **Um alle gefundenen gescannten Seiten zu erkennen,** klicke im Tab „Search“ auf **Run OCR**.
- Auch eine Suche startet die Erkennung, du kannst also einfach mit dem Suchen beginnen.

Hervorhebungen folgen dem Text, auch wenn die Seite leicht schräg gescannt wurde.

Text wird in den Sprachen aus den Einstellungen „Sprache & Region“ deines Mac erkannt, die die Erkennung unterstützt, oder auf Englisch, wenn sie keine davon unterstützt.

## Erkannten Text auswählen

Sobald eine Seite erkannt wurde, kannst du ihren Text wie auf jeder anderen Seite [auswählen und kopieren](select-text.md) sowie [hervorheben, unterstreichen oder durchstreichen](text-markup.md). Die Erkennung kann einen Moment dauern, und Seiten nach den ersten 50 benötigen zuerst Run OCR oder eine Suche.

Bei der Erkennung können Fehler passieren. Prüfe also alles, was du kopierst und was exakt sein muss. Auswahlen beginnen und enden sauber an Wortgrenzen. Innerhalb eines Wortes sind ihre Enden ungefähr.

> **Hinweis:** Erkannter Text wird verwendet, solange das Dokument geöffnet ist, und nicht im PDF gesichert, es sei denn, du sicherst ihn (siehe unten). Markierungen, die du hinzufügst, werden gesichert. Wenn du eine Seite schwärzt oder drehst, wird ihr Text neu erkannt.

## Erkannten Text im PDF sichern {#save-the-recognized-text-in-the-pdf}

Damit ein gescanntes PDF auch in anderen Apps wie Vorschau, Spotlight und Acrobat durchsuchbar ist, sichere den erkannten Text darin. Der Text wird als unsichtbare Ebene unter jede gescannte Seite gelegt, dort, wo er erkannt wurde, sodass die Seiten gleich aussehen.

- **Um ihn im Dokument zu sichern,** wähle File > Save with Recognized Text oder klicke im Tab „Search“ auf **Save in PDF**, sobald der Text erkannt ist. Deine anderen Änderungen werden ebenfalls gesichert.
- **Um ihn in einer Kopie zu sichern,** wähle File > Export Document As > Searchable PDF. Das geöffnete Dokument bleibt unverändert.

In beiden Fällen erkennt VectorPDF zuerst alle gescannten Seiten, die noch nicht erkannt sind, und zeigt den Fortschritt an. Das dauert pro Seite einen Moment. Du kannst auf „Cancel“ klicken, dann wird nichts gesichert.

Nur Seiten ohne eigenen Text erhalten Text. Sobald der Text in der Datei ist, gelten diese Seiten nicht mehr als gescannt: VectorPDF wählt den gesicherten Text aus und durchsucht ihn, wie es andere Apps tun.

> **Wichtig:** Die Erkennung kann Fehler machen, und gesicherter Text geht überallhin mit, wo die Datei hingeht: in Suchindizes, kopierten Text und Bildschirmleseprogramme. Prüfe, ob der Text stimmt, bevor du dich darauf verlässt, oder sichere stattdessen eine Kopie. Beim Sichern im Dokument wird es außerdem neu aus der Datei geöffnet, sodass du Änderungen von vor dem Sichern nicht widerrufen kannst.

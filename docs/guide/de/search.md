<!-- keywords: suchen, finden, weitersuchen, Groß-/Kleinschreibung, ganzes Wort, intelligente Suche, ignorierte Muster, regulärer Ausdruck, Tags, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, PDF -->
<!-- source: 4bafc06135d7 -->

# Ein Dokument durchsuchen

## Text finden

1. Drücke ⌘F. VectorPDF zeigt den Tab „Search“ in der Seitenleiste an.
2. Gib ein, wonach du suchst. Die Ergebnisse werden angezeigt, sobald sie gefunden werden, beginnend mit der aktuellen Seite.

Jedes Ergebnis zeigt seine Seite und den umgebenden Text, und jeder Treffer wird im Dokument hervorgehoben.

## Zwischen Ergebnissen wechseln

| Aktion | Vorgehensweise |
| --- | --- |
| Zum nächsten Ergebnis gehen | Drücke die Return-Taste oder ⌘G oder klicke auf den Abwärtspfeil |
| Zum vorherigen Ergebnis gehen | Drücke ⇧Return oder ⇧⌘G oder klicke auf den Aufwärtspfeil |
| Zu einem beliebigen Ergebnis gehen | Klicke darauf |
| Die Liste durchgehen | Klicke auf ein Ergebnis und drücke dann die Pfeiltasten |

Klicke mit der rechten Maustaste auf ein Ergebnis, um daraus [einen Anker zu erstellen](anchors.md) oder es in einem neuen Fenster zu öffnen.

## Suchoptionen {#search-options}

Klicke auf die Optionstaste neben dem Suchfeld:

- **Match Case:** Findet nur Text mit derselben Groß- und Kleinschreibung.
- **Whole Word:** Findet keine Treffer innerhalb längerer Wörter.
- **Smart Search:** Diese Option ist aktiviert, sofern du sie nicht deaktivierst. Leerzeichen, Bindestriche, Gedankenstriche und Zeilenumbrüche werden als gleichwertig behandelt, sodass „end-to-end“ auch „end to end“ findet, selbst über einen Zeilenumbruch hinweg. Auch gerade und typografische Anführungszeichen werden als gleichwertig behandelt.

## Störende Zeichen im Text ignorieren {#ignore-clutter-in-the-text}

Manche Dokumente enthalten mitten im Satz Markierungen wie Quellenangaben als Nummern, sodass eine Wortfolge nicht gefunden wird. Smart Search kann diese Markierungen überspringen.

1. Wähle VectorPDF > Settings.
2. Klicke neben „Ignored Search Patterns“ auf „Edit“.
3. Füge eines der vorgefertigten Muster oder deinen eigenen regulären Ausdruck hinzu und aktiviere es.

Die vorgefertigten Muster decken numerische Quellenangaben wie [12], Markensymbole, Star Paging wie *123 und Kommentar-Tags von IEEE 802.11 ab.

## Gescannte Dokumente

Gescannte Seiten enthalten keinen durchsuchbaren Text, bis er erkannt wurde. Weitere Informationen findest du unter [Text auf gescannten Seiten suchen und auswählen](scanned-pages.md).

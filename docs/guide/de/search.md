<!-- keywords: suchen, finden, weitersuchen, Groß-/Kleinschreibung, ganzes Wort, intelligente Suche, ignorierte Muster, regulärer Ausdruck, Tags, Suchverlauf, letzte Suchen, Abschnitt, Gliederung, Inhaltsverzeichnis, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, recent searches, search history, section, outline, table of contents, PDF -->
<!-- source: 0bf81b258540 -->

# Ein Dokument durchsuchen

## Text finden

1. Drücke ⌘F. VectorPDF zeigt den Tab „Search“ in der Seitenleiste an.
2. Gib ein, wonach du suchst. Die Ergebnisse werden angezeigt, sobald sie gefunden werden, beginnend mit der aktuellen Seite.

Die Ergebnisse werden nach Seite aufgelistet, jeweils mit dem umgebenden Text, und jeder Treffer wird im Dokument hervorgehoben. Hat das Dokument eine [Gliederung](outline-and-thumbnails.md), werden die Ergebnisse außerdem nach dem Abschnitt gruppiert, in dem sie stehen. Der Name des Abschnitts bleibt oben in der Liste, während du durch seine Ergebnisse scrollst. Um zu sehen, zu welchen übergeordneten Abschnitten er gehört, halte den Zeiger darüber.

## Zwischen Ergebnissen wechseln

| Aktion | Vorgehensweise |
| --- | --- |
| Zum nächsten Ergebnis gehen | Drücke die Return-Taste oder ⌘G oder klicke auf den Abwärtspfeil |
| Zum vorherigen Ergebnis gehen | Drücke ⇧Return oder ⇧⌘G oder klicke auf den Aufwärtspfeil |
| Zu einem beliebigen Ergebnis gehen | Klicke darauf |
| Die Liste durchgehen | Klicke auf ein Ergebnis und drücke dann die Pfeiltasten |

Klicke mit der rechten Maustaste auf ein Ergebnis, um daraus [einen Anker zu erstellen](anchors.md) oder es in einem neuen Fenster zu öffnen.

## Erneut nach etwas suchen, das du schon gesucht hast

Jedes Dokument merkt sich die letzten 10 Suchen, bei denen du zu einem Treffer gegangen bist. So suchst du erneut danach:

- Klicke auf die Lupe im Suchfeld und wähle die Suche aus, oder
- klicke bei leerem Suchfeld auf die Suche in der Liste Recent Searches unter dem Feld.

VectorPDF springt zum nächstgelegenen Treffer. Um die Suchen eines Dokuments zu vergessen, wähle Clear Recent Searches in der Lupe oder klicke über der Liste auf Clear. Auch das Anwenden von Schwärzungen auf ein Dokument löscht seine letzten Suchen.

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

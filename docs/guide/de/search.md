<!-- keywords: suchen, finden, weitersuchen, Groß-/Kleinschreibung, ganzes Wort, intelligente Suche, ignorierte Muster, regulärer Ausdruck, Tags, Suchverlauf, letzte Suchen, Abschnitt, Gliederung, Inhaltsverzeichnis, rechte Seite, neben der Gliederung, Suche verschieben, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, recent searches, search history, section, outline, table of contents, right side, beside the outline, move search, PDF -->
<!-- source: 9e3d931100aa -->

# Ein Dokument durchsuchen

## Text finden

1. Drücke ⌘F. VectorPDF zeigt den Tab „Search“ in der Seitenleiste an oder rechts im Fenster, wenn du ihn [dorthin verschoben hast](#see-results-beside-the-outline).
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

## Ergebnisse neben der Gliederung sehen {#see-results-beside-the-outline}

Um die Ergebnisse und die Gliederung gleichzeitig zu sehen, klicke auf die Optionstaste neben dem Suchfeld und wähle „Show Search on Right“. Die Suche wandert an den rechten Rand des Fensters, und die Seitenleiste zeigt die Gliederung oder, wenn das Dokument keine hat, die Seitenminiaturen. Jeder Gliederungseintrag mit Ergebnissen zeigt, wie viele es sind, und die Anzahl für den Abschnitt mit dem aktuellen Ergebnis ist hervorgehoben. Ein Abschnitt mit ausgeblendeten Unterabschnitten zählt auch deren Ergebnisse mit. Klickst du auf einen Gliederungseintrag, scrollt die Ergebnisliste zu den Ergebnissen dieses Abschnitts (oder zu denen seiner Unterabschnitte, wenn er selbst keine hat), während die Seite die Überschrift des Abschnitts zeigt. Das aktuelle Ergebnis bleibt, wo es war, bis du auf eines klickst.

Jedes Dokument merkt sich, auf welcher Seite du die Suche platziert hast. Um sie zurück in die Seitenleiste zu holen, wähle erneut „Show Search on Right“, um die Option auszuschalten. Um sie auszublenden, während sie rechts ist, klicke auf die Schließen-Taste (×) daneben. Um sie wieder einzublenden, drücke ⌘F oder klicke auf die Taste „Search“ oben in der Seitenleiste.

Die Suche teilt sich die rechte Seite mit dem [Inspector](rulers-and-inspector.md#the-inspector). Sind beide geöffnet, wechselst du mit den Tasten „Search“ und „Inspector“ oben zwischen ihnen.

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
- **Show Search on Right:** Verschiebt die Suche aus der Seitenleiste an den rechten Rand des Fensters, sodass du sie [neben der Gliederung](#see-results-beside-the-outline) sehen kannst.

## Störende Zeichen im Text ignorieren {#ignore-clutter-in-the-text}

Manche Dokumente enthalten mitten im Satz Markierungen wie Quellenangaben als Nummern, sodass eine Wortfolge nicht gefunden wird. Smart Search kann diese Markierungen überspringen.

1. Wähle VectorPDF > Settings und klicke dann auf „Advanced“.
2. Klicke neben „Ignored Search Patterns“ auf „Edit“.
3. Füge eines der vorgefertigten Muster oder deinen eigenen regulären Ausdruck hinzu und aktiviere es.

Die vorgefertigten Muster decken numerische Quellenangaben wie [12], Markensymbole, Star Paging wie *123 und Kommentar-Tags von IEEE 802.11 ab.

## Gescannte Dokumente

Gescannte Seiten enthalten keinen durchsuchbaren Text, bis er erkannt wurde. Weitere Informationen findest du unter [Text auf gescannten Seiten suchen und auswählen](scanned-pages.md).

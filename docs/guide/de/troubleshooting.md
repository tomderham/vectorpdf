<!-- keywords: damaged, corrupt, unreadable, Fehlerbehebung, Problem, Probleme, funktioniert nicht, Hilfe, beheben, Support, troubleshooting, problem, problems, not working, help, fix, support -->
<!-- source: 96d44ec3359c -->

# Fehlerbehebung

## Ich kann keinen Text auswählen, keinen Links folgen und keine Markierungswerkzeuge verwenden

Prüfe, ob die Ansicht gedreht ist oder sich im Two-Page Mode befindet. Diese Funktionen sind nur in der Darstellung „Single Page“ ohne Drehung verfügbar. Weitere Informationen findest du unter [Zoomen, Drehen und Seitenlayout](zoom-and-layout.md).

Prüfe außerdem, ob ein Werkzeug aus „Markup“ oder „Measurement“ aktiv ist. Drücke die Escape-Taste, um zur Textauswahl zurückzukehren.

## Eine Suche findet nichts

- Die Seiten sind möglicherweise gescannt. Weitere Informationen findest du unter [Text auf gescannten Seiten suchen und auswählen](scanned-pages.md).
- Prüfe, ob „Match Case“ und „Whole Word“ in den [Suchoptionen](search.md#search-options) deaktiviert sind und „Smart Search“ aktiviert ist.
- Wenn Markierungen den Text unterbrechen, füge ein [ignoriertes Muster](search.md#ignore-clutter-in-the-text) hinzu.

## Beim Halten von ⌘ wird keine Vorschau angezeigt

Link Peek funktioniert bei Links im Dokument und bei Weblinks zu Dokumenten, die in einem anderen Tab geöffnet sind. Verweise im Text sind keine Links. Klicke stattdessen mit der rechten Maustaste darauf. Weitere Informationen findest du unter [Verweise zwischen Dokumenten](cross-document-references.md).

Außerdem muss das VectorPDF-Fenster das aktive Fenster sein.

## Ein Verweis auf ein anderes Dokument wird nicht gefunden

Öffne das andere Dokument als Tab im selben Fenster. Separate Fenster werden nicht durchsucht.

## Ein Dokument wird als beschädigt gemeldet

Wenn VectorPDF in einer Datei keine Seiten findet, meldet es, dass die Datei nicht geöffnet werden konnte. Die Datei ist möglicherweise beschädigt oder unvollständig, oder sie verwendet Funktionen, die VectorPDF nicht lesen kann. Lade sie erneut herunter oder öffne sie in einer anderen PDF-App.

## Ein Cloud-Dokument lässt sich nicht öffnen

Prüfe deine Verbindung und ob die Datei im Finder geladen wird, und versuche es dann erneut.

## Der Agent ist nicht verfügbar oder zeigt nur Textstellen

Der Agent erfordert macOS 26 oder neuer. Damit Antworten auf dem Gerät verfasst werden können, muss Apple Intelligence aktiviert und bereit sein. Wenn das Indexieren fehlschlägt, klicke im Tab „Ask About This Document“ auf „Retry“. Weitere Informationen findest du unter [Festlegen, wie der Agent antwortet](agent-engines.md).

## Ein Online-Modell antwortet nicht

Prüfe den API-Schlüssel und das Modell in [Settings](settings.md) und ob dein Konto bei dem Dienst über Guthaben verfügt. VectorPDF antwortet auf dem Gerät, wenn der Dienst ausfällt.

## Meine Änderungen sind verschwunden

Änderungen müssen [gesichert](save.md) werden. Wenn eine andere App die Datei geändert hat, während du nicht gesicherte Änderungen hattest, werden sie durch die Auswahl von „Reload from Disk“ verworfen.

## Die Hilfe zeigt dieses Handbuch nicht an

Tips kann dieses Handbuch nur anzeigen, wenn sich VectorPDF in deinem Ordner „Programme“ befindet. Bewege die App dorthin und wähle dann erneut Help > VectorPDF Help.

## Weitere Hilfe

Melde ein Problem oder stelle eine Frage auf [GitHub](https://github.com/tomderham/vectorpdf/issues). Ein Beispiel-PDF hilft, wenn du eines teilen kannst.

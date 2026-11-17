<!-- keywords: sichern, speichern, sichern unter, nicht gesichert, teilen, im Finder anzeigen, Änderungen, zurücksetzen, letzte gesicherte Version, neu laden, verwerfen, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all, automatisch sichern, wiederherstellen, Wiederherstellung, Absturz, unerwartet beendet, autosave, recover, recovery, crash, quit unexpectedly -->
<!-- source: 722f6c80c23a -->

# Änderungen sichern

Markierungen, Formulareingaben, Seitenänderungen und Schwärzungen werden erst beim Sichern in deine Datei geschrieben. Bei einem Fenster mit nicht gesicherten Änderungen ist in der Schließen-Taste ein Punkt zu sehen.

| Aktion | Vorgehensweise |
| --- | --- |
| Sichern | Wähle File > Save oder drücke ⌘S |
| Kopie unter einem neuen Namen sichern | Wähle File > Save As oder drücke ⇧⌘S |
| Passwortgeschützte Kopie sichern | Wähle File > [Save Encrypted with Password](passwords.md) oder drücke ⌥⌘S |

Wenn du ein Dokument mit nicht gesicherten Änderungen schließt, fragt VectorPDF, ob du sie sichern möchtest.

## Änderungen verwerfen

Um alles seit dem letzten Sichern zu verwerfen, wähle File > Revert to Saved. VectorPDF fragt zuerst nach und öffnet dann die Datei so, wie sie zuletzt gesichert wurde, auf der Seite, die du gerade gelesen hast. Das Zurücksetzen kann nicht widerrufen werden.

Wie du eine kleinere Kopie eines Dokuments erstellst, erfährst du unter [Optimized PDF](export.md#optimized-pdf).

## Wenn VectorPDF unerwartet beendet wird {#if-vectorpdf-quits-unexpectedly}

Solange ein Dokument nicht gesicherte Änderungen hat, bewahrt VectorPDF eine Kopie davon auf deinem Mac auf, die etwa alle 30 Sekunden aktualisiert wird. Wird VectorPDF unerwartet beendet, bietet es die Kopien beim nächsten Öffnen an:

- **Open Recovered Copy** sichert jede Kopie neben ihrem Original mit dem Zusatz „(Recovered)“ und öffnet sie. Das Original bleibt unverändert. Vergleiche die beiden und behalte das, das du möchtest.
- **Decide Later** behält die Kopien und fragt beim nächsten Mal erneut.
- **Discard Changes** löscht die Kopien.

Die Kopie wird gelöscht, wenn du das Dokument sicherst, es auf die gesicherte Version zurücksetzt oder ohne Sichern schließt, und wenn du VectorPDF beendest. Passwortgeschützte Dokumente werden nicht kopiert, weil die Kopie nicht verschlüsselt wäre.

## Ein Dokument teilen

Wähle File > Share, um einen macOS-Freigabedienst zu verwenden, oder File > Show in Finder (⇧⌘R), um die Datei zu finden. Klicke auf dem Start-Bildschirm mit der rechten Maustaste auf ein Dokument, um es im Finder anzuzeigen.

## Was nicht im PDF gesichert wird

Einige Dinge bleiben bei VectorPDF und wandern nicht mit der Datei mit: [Anker](anchors.md), deine [Leseposition](reading-positions.md), die Drehung der Ansicht und Text aus der [OCR](scanned-pages.md), sofern du ihn nicht [im PDF sicherst](scanned-pages.md#save-the-recognized-text-in-the-pdf).

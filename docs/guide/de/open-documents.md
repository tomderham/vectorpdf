<!-- keywords: öffnen, PDF öffnen, Datei öffnen, PDF, zuletzt verwendet, Passwort, Cloud, neu laden, ziehen, E-Book, Comic, open, open PDF, open file, PDF, recent, password, cloud, iCloud Drive, Google Drive, Dropbox, OneDrive, Box, reload, drag, EPUB, e-book, ebook, XPS, OXPS, CBZ, comic, FB2, FictionBook -->
<!-- source: 076e48886ae4 -->

# Dokumente öffnen

## Ein PDF öffnen

- **In einem neuen Fenster:** Wähle File > Open PDF oder drücke ⌘O.
- **In einem neuen Tab:** Wähle File > Open PDF in New Tab oder drücke ⌥⌘O.
- **Im Finder:** Klicke mit der rechten Maustaste auf ein PDF und wähle dann „Öffnen mit“ > „VectorPDF“ (auf einem Mac mit englischer Systemsprache: Open With > VectorPDF). Um alle PDFs in VectorPDF zu öffnen, wähle ein PDF aus, wähle im Finder „Ablage“ > „Informationen“ (File > Get Info), ändere die Option „Öffnen mit“ und klicke dann auf „Alle ändern“ (Change All).
- **Durch Ziehen:** Ziehe ein PDF auf den Start-Bildschirm, um es dort zu öffnen, oder auf ein geöffnetes Dokument, um es in einem neuen Tab zu öffnen.
- **Aus einer Liste:** Wähle File > Open Recent oder verwende das Menü [Favorites](favorites-and-tab-groups.md). Klicke auf dem Start-Bildschirm mit der rechten Maustaste auf ein Dokument, um es in einem neuen Tab oder Fenster zu öffnen.

## E-Books, Comics und XPS-Dokumente

VectorPDF öffnet außerdem E-Books im Format EPUB und FictionBook (FB2), CBZ-Comicarchive und XPS-Dokumente, auf dieselbe Weise wie ein PDF. Ein E-Book wird zum Lesen in Seiten umbrochen.

Du kannst diese Dokumente lesen, ihrem Inhaltsverzeichnis folgen, sie durchsuchen, ihren Text auswählen und kopieren und [Anker](anchors.md) hinzufügen. Sie werden nur zum Lesen geöffnet: VectorPDF kann sie nicht sichern. Markieren, Messen, Schwärzen und Seitenbearbeitung sind daher nicht verfügbar, und „Save“ ist abgeblendet.

## Passwortgeschützte PDFs

VectorPDF fragt nach dem Passwort, wenn du ein geschütztes PDF öffnest. Weitere Informationen findest du unter [Passwörter und Verschlüsselung](passwords.md).

## PDFs im Cloud-Speicher

VectorPDF erkennt Dateien in iCloud Drive, Google Drive, Dropbox, OneDrive und Box. Wenn sich eine Datei noch nicht auf deinem Mac befindet, lädt VectorPDF sie vor dem Öffnen herunter und zeigt den Fortschritt an. Wird der Download nicht abgeschlossen, erhältst du eine Meldung und kannst es erneut versuchen, sobald du verbunden bist.

## Wenn sich eine Datei ändert

VectorPDF überwacht jede geöffnete Datei. Wenn eine andere App die Datei ändert, wird das Dokument automatisch neu geladen. Das ist nützlich, wenn du ein PDF mit LaTeX oder einem anderen Werkzeug erzeugst und es geöffnet lassen möchtest.

Wenn du nicht gesicherte Änderungen hast, fragt VectorPDF, ob **Reload from Disk** verwendet werden soll, wodurch deine Änderungen verloren gehen, oder **Keep My Changes**.

Wenn du eine Datei im Finder bewegst oder umbenennst, folgt ihr das geöffnete Dokument.

## Ein Dokument schließen

Schließe einen Tab oder ein Fenster wie gewohnt. Wenn es nicht gesicherte Änderungen gibt, fragt VectorPDF, ob du sie sichern möchtest. VectorPDF merkt sich für das nächste Mal, [wo du warst](reading-positions.md).

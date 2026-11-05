<!-- keywords: Anhänge, Anhang, angehängte Dateien, eingebettete Dateien, Büroklammer, Portfolio, E-Rechnung, elektronische Rechnung, Anhang sichern, attachments, attachment, attached files, embedded files, paperclip, portfolio, e-invoice, electronic invoice, ZUGFeRD, Factur-X, XML, Quick Look, save attachment, extract -->
<!-- source: e084e93b9409 -->

# An ein PDF angehängte Dateien

Ein PDF kann andere Dateien in sich tragen: eine Tabelle zu einem Bericht, ein CAD-Modell zu einem Plansatz oder die Daten einer elektronischen Rechnung. Wenn ein Dokument Anhänge hat, erscheint oben in der Seitenleiste der Tab „Attachments“ (eine Büroklammer). Ein Dokument mit einer oder zwei Seiten und Anhängen wird mit dem Tab „Attachments“ geöffnet.

Jeder Anhang zeigt seinen Namen und, sofern das PDF sie enthält, seine Beschreibung, Größe und die Seite, an die er angehängt ist. Halte den Zeiger über einen Anhang, um zu sehen, um welche Art von Datei es sich handelt und welches Datum sie hat.

| Aktion | Vorgehensweise |
| --- | --- |
| Vorschau eines Anhangs | Doppelklicke darauf, oder wähle ihn aus und drücke die Leertaste |
| Vorschau des nächsten oder vorherigen Anhangs | Drücke bei geöffnetem Quick Look die Abwärts- oder Aufwärtspfeiltaste |
| In seiner App öffnen | Klicke mit der rechten Maustaste darauf und wähle „Open“ |
| Eine Kopie sichern | Klicke mit der rechten Maustaste darauf und wähle „Save As…“, oder ziehe ihn in den Finder |
| Alle sichern | Klicke oben im Tab auf „Save All…“ und wähle einen Ordner |
| Zu seiner Seite wechseln | Klicke mit der rechten Maustaste darauf und wähle „Show on Page“ |

> **Warnung:** Ein Anhang kann jede Art von Datei sein, auch eine App oder ein Skript. Öffne nur Dateien, denen du vertraust. VectorPDF markiert die Dateien, die es aus einem PDF holt, als geladen, sodass macOS Apps und Skripte vor dem Ausführen prüft, wie bei Dateien aus dem Internet.

## Elektronische Rechnungen

ZUGFeRD- und Factur-X-Rechnungen tragen ihre Daten in einer XML-Datei, meist `factur-x.xml` oder `zugferd-invoice.xml` genannt. Sie wird mit den anderen Anhängen aufgeführt, sodass du sie für deine Buchhaltungssoftware sichern kannst. VectorPDF zeigt die Details der Rechnung nicht selbst an.

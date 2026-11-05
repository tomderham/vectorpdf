<!-- keywords: Datenschutz, Daten, Netzwerk, Telemetrie, Analysedaten, Sicherheit, letzte Suchen, privacy, data, network, telemetry, analytics, iCloud, security -->
<!-- source: 936fa61fbdbf -->

# Datenschutz

VectorPDF hat keine Accounts, keine Analysefunktionen, keine Telemetrie und keine Absturzberichte. Deine Dokumente werden auf deinem Mac verarbeitet, und nichts davon wird an den Entwickler gesendet.

## Was das Netzwerk verwendet

- **Suche nach Updates:** VectorPDF fragt etwa einmal am Tag oder wenn du „Check for Updates“ wählst bei GitHub nach der neuesten Version. Die Anfrage enthält keine Informationen über dich oder deine Dokumente. Du kannst das in [Settings](settings.md) deaktivieren.
- **Agent:** Mit der Engine „On-Device“ verlässt nichts deinen Mac. [Private Cloud Compute und Online-Modelle](agent-engines.md) senden deine Frage und Textstellen aus dem Dokument, und das nur, wenn du eine Frage stellst. Beim Einrichten eines Online-Modells wird dein Schlüssel außerdem verwendet, um die Modelle aufzulisten und einen kurzen Test zu senden.
- **iCloud:** Dein Lesestatus wird in deinem eigenen iCloud-Account aufbewahrt: wo sich die Datei befindet, die letzte Seite und Zoomstufe sowie Namen, Textauszüge und Seiten deiner Anker. Dokumente, ihr vollständiger Text und Miniaturen von Ankern werden nicht hochgeladen. Auch deine letzten Suchen werden dort gespeichert.
- **Links, auf die du klickst,** werden in deinem Browser geöffnet.
- **Apple-Dienste:** Übersetzen, Nachschlagen, Sprachausgabe und OCR werden von macOS bereitgestellt und laden möglicherweise Sprachdateien von Apple. Handoff teilt das Dokument und die Seite, die du gerade liest, mit deinen anderen Geräten.

## Was auf deinem Mac gespeichert wird

VectorPDF speichert deine Einstellungen, Favoriten, Tabgruppen, Lesepositionen, Anker und deinen Stempel. Außerdem bewahrt es einen Index für Dokumente auf, die du mit dem Agenten verwendet hast, sowie Miniaturen von Ankern und temporäre Arbeitskopien von Dokumenten mit nicht gesicherten Seitenänderungen oder Schwärzungen, die es löscht, sobald sie nicht mehr benötigt werden.

Auch die letzten Suchen jedes Dokuments werden gespeichert. Wie viel Platz das belegt, siehst und löschst du unter „Storage“ in den [Einstellungen](settings.md#free-up-space-or-remove-data).

API-Schlüssel für Online-Modelle werden in deinem Schlüsselbund „Anmeldung“ gespeichert.

Alle Details findest du in der [Datenschutzrichtlinie auf GitHub](https://github.com/tomderham/vectorpdf/blob/main/PRIVACY.md).

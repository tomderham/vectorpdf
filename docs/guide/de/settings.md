<!-- keywords: Einstellungen, Optionen, Updates, Update, nach Updates suchen, Browser, Autor, Anmerkungsautor, Speicher, Speicherplatz, löschen, Daten entfernen, deinstallieren, settings, preferences, options, updates, update, check for updates, browser, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->
<!-- source: 91c5b0e9ab3d -->

# Einstellungen

Wähle VectorPDF > Settings oder drücke ⌘,.

| Einstellung | Funktion |
| --- | --- |
| Annotation Author | Der Name, der mit deinen Anmerkungen und Antworten gesichert wird. Wenn das Feld leer ist, verwendet VectorPDF deinen Mac-Benutzernamen. |
| Use Agent | Zeigt den Tab „[Ask About This Document](agent.md)“ in der Seitenleiste an, unter macOS 26 oder neuer. |
| AI Synthesis Engine | Legt fest, [was die Antworten des Agenten verfasst](agent-engines.md), unter macOS 27. |
| PDF Color | Legt fest, [wie Seiten aussehen](pdf-colors.md): Follow System, Light, Dark oder Sepia. |
| Open Links In | Legt den Browser für Weblinks fest. |
| LaTeX (SyncTeX) | Legt den Editor fest, der den [LaTeX-Quelltext](latex.md) öffnet, wenn du bei gedrückten ⇧⌘-Tasten in ein PDF klickst. |
| Ignored Search Patterns | Listet Text auf, den [Smart Search überspringt](search.md#ignore-clutter-in-the-text). |
| Digital Stamp | Erstellt, ändert oder löscht deinen [Stempel](stamps.md). |
| Sync reading positions with iCloud | Hält deine [Seite, Zoomstufe, Anker](reading-positions.md) und [letzten Suchen](search.md) auf deinen anderen Macs aktuell. |
| Storage | Zeigt, wie viel Platz die Daten von VectorPDF belegen, und [löscht sie](#free-up-space-or-remove-data). |
| Automatically check for updates | Sucht etwa einmal am Tag auf GitHub nach einer neuen Version. Klicke auf „Check Now“, um jederzeit zu suchen. |

## Speicherplatz freigeben oder Daten entfernen {#free-up-space-or-remove-data}

Unter „Storage“ zeigen die Einstellungen, wie viel Platz jede Art von Daten belegt:

- **Agent-Indizes:** Was der Agent erstellt, um Fragen zu einem Dokument zu beantworten. Klicke auf „Clear“, um sie zu löschen; ein Dokument wird erneut indiziert, wenn du den Agenten das nächste Mal damit verwendest. VectorPDF hält sie unter 500 MB, indem es die am längsten nicht verwendeten zuerst löscht, und löscht den Index eines Dokuments, wenn das Dokument nicht mehr existiert.
- **Leseverlauf:** Die letzte Seite, Zoomstufe, Anker und letzten Suchen jedes Dokuments. Klicke auf „Clear“, um sie zu vergessen, auf diesem Mac und in iCloud.
- **Temporäre Dateien:** Kopien, die beim Bearbeiten, Sichern, Drucken oder Exportieren entstehen, und geladene Updates. VectorPDF löscht übrig gebliebene beim nächsten Öffnen.

Um alles zu entfernen, was VectorPDF gespeichert hat, klicke auf „Remove All VectorPDF Data“. Dabei werden auch deine Einstellungen, Favoriten, Tabgruppen, dein Stempel und deine API-Schlüssel entfernt, dann wird VectorPDF beendet. Deine Dokumente bleiben unverändert. Sichere oder schließe vorher alle Dokumente mit ungesicherten Änderungen.

## VectorPDF aktualisieren

Wähle VectorPDF > Check for Updates. Wenn eine neue Version verfügbar ist, klicke auf „Download“. Klicke nach dem Download auf **Quit and Open Installer** und ziehe VectorPDF dann in deinen Ordner „Programme“.

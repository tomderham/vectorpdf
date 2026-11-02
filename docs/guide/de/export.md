<!-- keywords: exportieren, konvertieren, reiner Text, Text, Word, reduzieren, Anmerkungsübersicht, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF -->
<!-- source: bfda5c49e81e -->

# In andere Formate exportieren

Um ein ganzes Dokument zu exportieren, wähle File > Export Document As und dann Plain Text, Word Document, Scalable Vector Graphics oder Flattened PDF. Für die Anmerkungsübersicht und Messungen gibt es eigene Befehle.

## Plain Text

Sichert den Text des Dokuments als `.txt`-Datei.

## Word Document

Sichert eine `.docx`-Datei, die du in Word und anderen Apps bearbeiten kannst. Komplexe Seitenlayouts können anders aussehen als im PDF.

## SVG

Sichert jede Seite als SVG-Datei (Scalable Vector Graphics). Text wird dabei in Vektorpfade umgewandelt, sodass die Seite genau wie im PDF aussieht. Ein mehrseitiges Dokument wird als Ordner mit einer Datei pro Seite gesichert.

## Flattened PDF {#flattened-pdf}

Sichert ein PDF, in dem Anmerkungen und Formularfelder fest in die Seite eingebettet sind, sodass sie nicht mehr geändert werden können. Wähle im Dialogfenster zum Sichern aus, was reduziert werden soll:

- **Flatten annotations and markups**
- **Flatten form fields (make static)**

> **Hinweis:** Beim Reduzieren wird nicht entfernt, was darunter liegt. Um Inhalte zu entfernen, verwende die [Schwärzung](redact.md).

## Anmerkungsübersicht

Wähle File > Export Annotations Summary (⇧⌘E), um eine Liste deiner Anmerkungen zu sichern. Standardmäßig ist das eine Markdown-Datei. Gib der Datei die Endung `.csv`, um stattdessen eine Tabelle zu sichern.

## Messungen

Verwende zum Exportieren von Messungen die [Takeoff-Tabelle](takeoff.md).

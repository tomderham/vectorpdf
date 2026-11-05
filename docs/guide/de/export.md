<!-- keywords: exportieren, konvertieren, reiner Text, Text, Word, reduzieren, Anmerkungsübersicht, optimieren, optimiert, Dateigröße verringern, komprimieren, kleiner, Bilder, Schriften, Konturen, Text in Konturen, Plotter, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF, optimize, optimized, reduce file size, compress, smaller, downsample, images, fonts, subset, outlines, text to outlines, plotter -->
<!-- source: 0e99b5515751 -->

# In andere Formate exportieren

Um ein ganzes Dokument zu exportieren, wähle File > Export Document As und dann Plain Text, Word Document, Scalable Vector Graphics, Flattened PDF oder Optimized PDF. Für die Anmerkungsübersicht und Messungen gibt es eigene Befehle.

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

## Optimized PDF {#optimized-pdf}

Sichert eine kleinere Kopie des PDF, einschließlich aller Änderungen, die du noch nicht gesichert hast. Das geöffnete Dokument bleibt unverändert. Daten, die das Dokument nicht mehr verwendet, werden entfernt, Duplikate zusammengeführt und alles wird komprimiert. Im Dialogfenster zum Sichern kannst du außerdem Folgendes wählen:

- **Keep only the characters each font uses:** Entfernt die Teile eingebetteter Schriften, die das Dokument nicht verwendet. Standardmäßig aktiviert.
- **Images:** Belasse Bilder unverändert oder verringere sie auf 300 dpi (zum Drucken) oder 150 dpi (zum Lesen am Bildschirm). Nur Bilder mit höherer Auflösung werden verkleinert. Fotos werden als JPEG gesichert, Diagramme und Bildschirmfotos bleiben verlustfrei. Schwarzweiß-Scans bleiben unverändert.
- **Convert text to outlines:** Zeichnet jeden Buchstaben als Form, sodass das Dokument auf Plottern, Schneidegeräten und Drucksystemen, die seine Schriften nicht haben, gleich aussieht. Text in der Kopie kann nicht ausgewählt, durchsucht oder kopiert werden.

Wie viel kleiner die Kopie wird, hängt vom Dokument ab. Scans und Fotos schrumpfen am stärksten, wenn du ihre Bilder verkleinerst.

## Anmerkungsübersicht

Wähle File > Export Annotations Summary (⇧⌘E), um eine Liste der Anmerkungen des Dokuments zu sichern, einschließlich der Anmerkungen aus anderen Apps, mit ihren Autoren, Status und Antworten. Standardmäßig ist das eine Markdown-Datei. Gib der Datei die Endung `.csv`, um stattdessen eine Tabelle zu sichern.

## Messungen

Verwende zum Exportieren von Messungen die [Takeoff-Tabelle](takeoff.md).

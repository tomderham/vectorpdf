<!-- keywords: schwärzen, Schwärzung, Schwärzungen, entfernen, vertraulich, Sozialversicherungsnummer, Kreditkarte, E-Mail, Telefon, Datum, suchen und schwärzen, redact, redaction, redactions, remove, black out, sensitive, SSN, credit card, email, phone, date, find and redact, PDF -->
<!-- source: 90945f068642 -->

# Vertrauliche Inhalte schwärzen

Beim Schwärzen werden Inhalte dauerhaft aus einem PDF entfernt. VectorPDF löscht Text, Bildpixel und Vektorgrafiken unter dem geschwärzten Bereich aus der Datei, außerdem alle Anmerkungen und Formularfelder, die ihn berühren. Die Inhalte werden nicht nur mit einem Kasten abgedeckt, und frühere Versionen werden beim Sichern nicht behalten.

> **Warnung:** Eine Schwärzung wird sofort wirksam, sobald du sie anwendest, und es gibt kein Undo. Deine Originaldatei ändert sich erst, wenn du sicherst. Um neu zu beginnen, schließe das Dokument also ohne zu sichern. Bewahre eine Kopie des Originals auf und verwende „Save As“, um die geschwärzte Version unter einem neuen Namen zu sichern.

Drücke ⌥⌘R oder wähle View > Show Redact Toolbar.

## Einen Bereich schwärzen

1. Wähle **Redact Region**.
2. Wähle „Black“ oder „White“ als Schwärzungsfarbe.
3. Ziehe über den Bereich, den du schwärzen möchtest.

## Suchen und schwärzen

1. Wähle **Find & Redact**.
2. Wähle aus, wonach gesucht werden soll:
   - **Text / Phrase**, mit den Optionen „Match Case“ und „Whole Word“.
   - **Custom Regular Expression**, zum Beispiel `[A-Z]{3}-\d{5}`.
   - **Social Security Number (SSN)**, **Credit Card Number**, **Email Address**, **Phone Number** oder **Date**. Damit werden gängige Formate automatisch gefunden.
3. Klicke auf „Find“.
4. Prüfe die Treffer. Klicke auf einen Treffer, um ihn auf seiner Seite zu sehen, und hebe die Auswahl aller Treffer auf, die du behalten möchtest.
5. Wähle eine Aktion aus:
   - **Redact** entfernt den Inhalt und hinterlässt einen schwarzen oder weißen Kasten.
   - **Remove** entfernt den Inhalt und hinterlässt keinen Kasten.
6. Klicke auf **Redact Selected** oder **Remove Selected**.

> **Warnung:** Die automatische Erkennung kann etwas übersehen, besonders ungewöhnliche Formate oder Text in Bildern. Prüfe das Dokument, bevor du es weitergibst. Text auf gescannten Seiten muss mit „Redact Region“ geschwärzt werden.

## Das Ergebnis sichern

Drücke ⇧⌘S, um das geschwärzte Dokument unter einem neuen Namen zu sichern. Beim Sichern wird auch der Suchindex des [Agenten](agent.md) für das Dokument gelöscht, da er den entfernten Text enthalten könnte.

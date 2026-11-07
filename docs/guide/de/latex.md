<!-- keywords: LaTeX, TeX, SyncTeX, Vorwärtssuche, Rückwärtssuche, Quelltext, Quelle, Editor, zur Quelle springen, LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->
<!-- source: a865c846e0d7 -->

# LaTeX-Quelltext und PDF verbinden

Wenn du in LaTeX schreibst, bringt dich VectorPDF von einer Stelle im PDF zur Quelltextzeile, die sie erzeugt hat, und von einer Quelltextzeile zur Stelle, die sie im PDF erzeugt hat. Dafür wird SyncTeX verwendet, das TeX einschaltet, wenn es mit `-synctex=1` erstellt. Die meisten LaTeX-Editoren erstellen so.

SyncTeX funktioniert mit einem PDF, neben dem seine SyncTeX-Datei liegt, benannt nach dem PDF: `paper.pdf` und `paper.synctex.gz`. Andere PDFs im Ordner sind davon nicht betroffen.

## Editor wählen

1. Wähle VectorPDF > Settings und klicke dann neben „LaTeX (SyncTeX)“ auf „Set Up…“.
2. Wähle deinen Editor unter „Source Editor“: Visual Studio Code, VSCodium, Cursor, Zed, Sublime Text, BBEdit, TextMate, MacVim, Emacs oder TeXstudio.
3. Ist dein Editor nicht aufgeführt, wähle „Other“ und gib den Befehl ein, der eine Datei an einer Zeile öffnet. Schreibe `%file` für die Datei und `%line` für die Zeile, etwa `myeditor +%line %file`.

Unter dem Editor zeigt Settings das gefundene Programm an. Steht dort, dass das Programm nicht gefunden wurde, installiere das Befehlszeilenwerkzeug deines Editors, oder wähle „Other“ und gib den vollständigen Pfad des Programms an.

## Vom PDF zum Quelltext

Klicke bei gedrückten ⇧⌘-Tasten auf eine Stelle im PDF. Dein Editor öffnet die Quelldatei an der Zeile, die sie erzeugt hat.

Du kannst auch mit der rechten Maustaste klicken und **Show in Editor** wählen. Der Befehl steht oben im Menü eines PDFs mit SyncTeX-Datei.

## Vom Quelltext zum PDF

Dein Editor bittet VectorPDF, eine Zeile anzuzeigen, indem er `displayline` ausführt, das mit VectorPDF geliefert wird:

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

VectorPDF holt das PDF nach vorn, öffnet es, falls es nicht geöffnet ist, und hebt die Zeile kurz rot hervor. Es scrollt nur, wenn die Zeile nicht schon zu sehen ist. Setze `-g` vor LINE, damit VectorPDF hinter deinem Editor bleibt.

`displayline` nimmt dieselben Argumente wie das von Skim. Hat dein Editor eine Einstellung für Skim, verwende dort stattdessen das `displayline` von VectorPDF.

### Visual Studio Code

Füge mit der Erweiterung LaTeX Workshop diese Zeilen zu deinen Einstellungen hinzu. Du findest sie, indem du in der Befehlspalette „Preferences: Open User Settings (JSON)“ wählst.

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

Drücke dann in Visual Studio Code ⌥⌘B zum Erstellen, ⌥⌘V, um das PDF in VectorPDF zu öffnen, und ⌥⌘J, um die Zeile anzuzeigen, in der du bist. Mit der letzten Einstellung zeigt VectorPDF diese Zeile auch nach jedem Erstellen an.

## Während du schreibst

Wenn dein Editor das PDF neu erstellt, lädt VectorPDF es neu und behält deine Position, den Zoom, die Drehung und das Seitenlayout bei. Wird die Datei noch geschrieben, wartet VectorPDF, bis sie fertig ist.

## Wenn es nicht funktioniert

- **„Show in Editor“ fehlt im Menü:** Das PDF hat keine SyncTeX-Datei. Erstelle es mit eingeschaltetem SyncTeX, und lass die SyncTeX-Datei neben dem PDF oder in einem Ordner namens build oder out daneben.
- **„No Source Here“:** Für diese Stelle gibt es keine Quelltextzeile, etwa an einem Rand oder in einem Bild. Klicke auf Text.
- **In VectorPDF passiert nichts:** Prüfe, ob dein Editor das `displayline` von VectorPDF ausführt und ob das PDF seit deiner letzten Änderung am Quelltext mit eingeschaltetem SyncTeX erstellt wurde.
- **Dein Editor findet TeX nach der Installation nicht:** Beende den Editor und öffne ihn erneut.

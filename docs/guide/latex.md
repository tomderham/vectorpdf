<!-- keywords: LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->

# Go between LaTeX source and the PDF

If you write in LaTeX, VectorPDF can take you from a place in the PDF to the line of source that made it, and from a line of source to the place it made in the PDF. This uses SyncTeX, which TeX turns on when it builds with `-synctex=1`. Most LaTeX editors build that way.

SyncTeX works with a PDF that has its SyncTeX file beside it, named after the PDF: `paper.pdf` and `paper.synctex.gz`. Other PDFs in the folder aren't affected.

## Choose your editor

1. Choose VectorPDF > Settings, then click **Set Up…** next to LaTeX (SyncTeX).
2. Choose your editor from Source Editor: Visual Studio Code, VSCodium, Cursor, Zed, Sublime Text, BBEdit, TextMate, MacVim, Emacs or TeXstudio.
3. If your editor isn't listed, choose Other, and enter the command that opens a file at a line. Write `%file` for the file and `%line` for the line, such as `myeditor +%line %file`.

Under the editor, Settings shows the program it found. If it says the program wasn't found, install your editor's command-line tool, or choose Other and give the program's full path.

## Go from the PDF to the source

⇧⌘-click a place in the PDF. Your editor opens the source file at the line that made it.

You can also right-click and choose **Show in Editor**. It's at the top of the menu for a PDF with a SyncTeX file.

## Go from the source to the PDF

Your editor asks VectorPDF to show a line by running `displayline`, which comes with VectorPDF:

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

VectorPDF brings the PDF forward, opening it if it isn't open, and highlights the line in red for a moment. It scrolls only if the line isn't already on screen. Add `-g` before LINE to leave VectorPDF behind your editor.

`displayline` takes the same arguments as Skim's. If your editor has a setting for Skim, use VectorPDF's `displayline` in its place.

### Visual Studio Code

With the LaTeX Workshop extension, add these lines to your settings. To find them, choose Preferences: Open User Settings (JSON) from the Command Palette.

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

Then, in Visual Studio Code, press ⌥⌘B to build, ⌥⌘V to open the PDF in VectorPDF, and ⌥⌘J to show the line you're on. With the last setting, VectorPDF also shows that line after every build.

## While you write

When your editor builds the PDF again, VectorPDF reloads it and keeps your place, zoom, rotation and page layout. If the file is still being written, VectorPDF waits until it's finished.

## If it doesn't work

- **Show in Editor isn't in the menu:** the PDF has no SyncTeX file. Build with SyncTeX on, and keep the SyncTeX file beside the PDF, or in a folder named build or out beside it.
- **No Source Here:** there's no line of source for that place, such as a margin or a picture. Click on text.
- **Nothing happens in VectorPDF:** check that your editor runs VectorPDF's `displayline`, and that the PDF has been built with SyncTeX on since you last changed the source.
- **Your editor can't find TeX after you installed it:** quit the editor and open it again.

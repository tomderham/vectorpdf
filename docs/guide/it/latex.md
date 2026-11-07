<!-- keywords: LaTeX, TeX, SyncTeX, ricerca diretta, ricerca inversa, sorgente, codice sorgente, editor, vai al sorgente, LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->
<!-- source: a865c846e0d7 -->

# Passare dal sorgente LaTeX al PDF

Se scrivi in LaTeX, VectorPDF può portarti da un punto del PDF alla riga del sorgente che lo ha generato, e da una riga del sorgente al punto che ha generato nel PDF. Per farlo usa SyncTeX, che TeX attiva quando compila con `-synctex=1`. La maggior parte degli editor LaTeX compila così.

SyncTeX funziona con un PDF che ha accanto il suo file SyncTeX, con lo stesso nome del PDF: `paper.pdf` e `paper.synctex.gz`. Gli altri PDF nella cartella non sono interessati.

## Scegliere l'editor

1. Scegli VectorPDF > Settings, poi fai clic su Set Up… accanto a LaTeX (SyncTeX).
2. Scegli il tuo editor in Source Editor: Visual Studio Code, VSCodium, Cursor, Zed, Sublime Text, BBEdit, TextMate, MacVim, Emacs o TeXstudio.
3. Se il tuo editor non è nell'elenco, scegli Other e inserisci il comando che apre un file a una riga. Scrivi `%file` per il file e `%line` per la riga, ad esempio `myeditor +%line %file`.

Sotto l'editor, Settings mostra il programma trovato. Se dice che il programma non è stato trovato, installa lo strumento da riga di comando del tuo editor, oppure scegli Other e indica il percorso completo del programma.

## Dal PDF al sorgente

Fai clic su un punto del PDF tenendo premuti ⇧⌘. Il tuo editor apre il file sorgente alla riga che lo ha generato.

Puoi anche fare clic con il tasto destro e scegliere **Show in Editor**. Si trova in cima al menu di un PDF con un file SyncTeX.

## Dal sorgente al PDF

Il tuo editor chiede a VectorPDF di mostrare una riga eseguendo `displayline`, incluso in VectorPDF:

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

VectorPDF porta il PDF in primo piano, lo apre se non è aperto ed evidenzia per un momento la riga in rosso. Scorre solo se la riga non è già sullo schermo. Aggiungi `-g` prima di LINE per lasciare VectorPDF dietro l'editor.

`displayline` accetta gli stessi argomenti di quello di Skim. Se il tuo editor ha un'impostazione per Skim, usa al suo posto il `displayline` di VectorPDF.

### Visual Studio Code

Con l'estensione LaTeX Workshop, aggiungi queste righe alle impostazioni. Per trovarle, scegli Preferences: Open User Settings (JSON) dal riquadro comandi.

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

Poi, in Visual Studio Code, premi ⌥⌘B per compilare, ⌥⌘V per aprire il PDF in VectorPDF e ⌥⌘J per mostrare la riga in cui ti trovi. Con l'ultima impostazione, VectorPDF mostra quella riga anche dopo ogni compilazione.

## Mentre scrivi

Quando l'editor compila di nuovo il PDF, VectorPDF lo ricarica mantenendo la posizione, lo zoom, la rotazione e il layout delle pagine. Se il file è ancora in scrittura, VectorPDF attende che sia completo.

## Se non funziona

- **Show in Editor non è nel menu:** il PDF non ha un file SyncTeX. Compila con SyncTeX attivo e tieni il file SyncTeX accanto al PDF, oppure in una cartella chiamata build o out accanto a esso.
- **No Source Here:** non c'è una riga del sorgente per quel punto, come un margine o un'immagine. Fai clic sul testo.
- **In VectorPDF non succede nulla:** controlla che il tuo editor esegua il `displayline` di VectorPDF e che il PDF sia stato compilato con SyncTeX attivo dopo l'ultima modifica al sorgente.
- **L'editor non trova TeX dopo l'installazione:** chiudi l'editor e riaprilo.

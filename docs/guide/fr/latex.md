<!-- keywords: LaTeX, TeX, SyncTeX, recherche directe, recherche inverse, code source, source, éditeur, aller à la source, LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->
<!-- source: a865c846e0d7 -->

# Passer du code LaTeX au PDF

Si vous écrivez en LaTeX, VectorPDF peut vous emmener d’un endroit du PDF à la ligne de code qui l’a produit, et d’une ligne de code à l’endroit qu’elle a produit dans le PDF. Il utilise pour cela SyncTeX, que TeX active lorsqu’il compile avec `-synctex=1`. La plupart des éditeurs LaTeX compilent ainsi.

SyncTeX fonctionne avec un PDF accompagné de son fichier SyncTeX, qui porte le nom du PDF : `paper.pdf` et `paper.synctex.gz`. Les autres PDF du dossier ne sont pas concernés.

## Choisir votre éditeur

1. Choisissez VectorPDF > Settings, puis cliquez sur Set Up… à côté de LaTeX (SyncTeX).
2. Choisissez votre éditeur dans Source Editor : Visual Studio Code, VSCodium, Cursor, Zed, Sublime Text, BBEdit, TextMate, MacVim, Emacs ou TeXstudio.
3. Si votre éditeur n’est pas dans la liste, choisissez Other, puis saisissez la commande qui ouvre un fichier à une ligne. Écrivez `%file` pour le fichier et `%line` pour la ligne, par exemple `myeditor +%line %file`.

Sous l’éditeur, Settings indique le programme trouvé. S’il indique que le programme est introuvable, installez l’outil en ligne de commande de votre éditeur, ou choisissez Other et donnez le chemin complet du programme.

## Aller du PDF au code

Cliquez sur un endroit du PDF en maintenant ⇧⌘. Votre éditeur ouvre le fichier source à la ligne qui l’a produit.

Vous pouvez aussi cliquer avec le bouton droit et choisir **Show in Editor**. Cette commande se trouve en haut du menu d’un PDF qui a un fichier SyncTeX.

## Aller du code au PDF

Votre éditeur demande à VectorPDF d’afficher une ligne en exécutant `displayline`, fourni avec VectorPDF :

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

VectorPDF met le PDF au premier plan, l’ouvre s’il n’est pas ouvert et surligne brièvement la ligne en rouge. Il ne fait défiler la page que si la ligne n’est pas déjà à l’écran. Ajoutez `-g` avant LINE pour laisser VectorPDF derrière votre éditeur.

`displayline` accepte les mêmes arguments que celui de Skim. Si votre éditeur a un réglage pour Skim, utilisez à la place le `displayline` de VectorPDF.

### Visual Studio Code

Avec l’extension LaTeX Workshop, ajoutez ces lignes à vos réglages. Pour les trouver, choisissez Preferences: Open User Settings (JSON) dans la palette de commandes.

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

Ensuite, dans Visual Studio Code, appuyez sur ⌥⌘B pour compiler, ⌥⌘V pour ouvrir le PDF dans VectorPDF et ⌥⌘J pour afficher la ligne où vous êtes. Avec le dernier réglage, VectorPDF affiche aussi cette ligne après chaque compilation.

## Pendant que vous écrivez

Quand votre éditeur compile de nouveau le PDF, VectorPDF le recharge en conservant votre position, le zoom, la rotation et la disposition des pages. Si le fichier est encore en cours d’écriture, VectorPDF attend qu’il soit terminé.

## Si cela ne fonctionne pas

- **Show in Editor n’est pas dans le menu :** le PDF n’a pas de fichier SyncTeX. Compilez avec SyncTeX activé, et gardez le fichier SyncTeX à côté du PDF, ou dans un dossier nommé build ou out à côté de celui-ci.
- **No Source Here :** il n’y a pas de ligne de code pour cet endroit, comme une marge ou une image. Cliquez sur du texte.
- **Rien ne se passe dans VectorPDF :** vérifiez que votre éditeur exécute le `displayline` de VectorPDF, et que le PDF a été compilé avec SyncTeX activé depuis votre dernière modification du code.
- **Votre éditeur ne trouve pas TeX après son installation :** quittez l’éditeur, puis rouvrez-le.

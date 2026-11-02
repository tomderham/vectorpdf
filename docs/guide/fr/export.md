<!-- keywords: exporter, convertir, texte brut, texte, aplatir, aplati, résumé des annotations, tableur, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF -->
<!-- source: c72be921ec25 -->

# Exporter vers d’autres formats

Pour exporter un document entier, choisissez File > Export Document As, puis choisissez Plain Text, Word Document, Scalable Vector Graphics ou Flattened PDF. Le résumé des annotations et les mesures ont leurs propres commandes.

## Texte brut

Enregistre le texte du document dans un fichier `.txt`.

## Document Word

Enregistre un fichier `.docx` que vous pouvez modifier dans Word et d’autres apps. Les mises en page complexes peuvent différer de celle du PDF.

## SVG

Enregistre chaque page dans un fichier SVG (Scalable Vector Graphics), avec le texte sous forme de tracés vectoriels, pour un rendu identique à celui du PDF. Un document de plusieurs pages est enregistré dans un dossier contenant un fichier par page.

## PDF aplati {#flattened-pdf}

Enregistre un PDF dont les annotations et les champs de formulaire font partie intégrante de la page et ne peuvent donc plus être modifiés. Dans la zone de dialogue d’enregistrement, choisissez ce qu’il faut aplatir :

- **Flatten annotations and markups**
- **Flatten form fields (make static)**

> **Remarque :** L’aplatissement ne supprime pas ce qui se trouve en dessous. Pour retirer du contenu, utilisez le [caviardage](redact.md).

## Résumé des annotations

Choisissez File > Export Annotations Summary (⇧⌘E) pour enregistrer la liste des annotations du document, y compris celles d’autres apps, avec leurs auteurs, statuts et réponses. Par défaut, il s’agit d’un fichier Markdown. Donnez au fichier l’extension `.csv` pour enregistrer plutôt une feuille de calcul.

## Mesures

Pour exporter des mesures, utilisez le [tableau de métré](takeoff.md).

<!-- keywords: exporter, convertir, texte brut, texte, aplatir, aplati, résumé des annotations, tableur, optimiser, optimisé, réduire la taille, compresser, plus léger, images, polices, contours, vectoriser le texte, traceur, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF, optimize, optimized, reduce file size, compress, smaller, downsample, images, fonts, subset, outlines, text to outlines, plotter -->
<!-- source: 0e99b5515751 -->

# Exporter vers d’autres formats

Pour exporter un document entier, choisissez File > Export Document As, puis choisissez Plain Text, Word Document, Scalable Vector Graphics, Flattened PDF ou Optimized PDF. Le résumé des annotations et les mesures ont leurs propres commandes.

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

## PDF optimisé {#optimized-pdf}

Enregistre une copie plus légère du PDF, y compris les modifications que vous n’avez pas encore enregistrées. Le document ouvert ne change pas. Les données que le document n’utilise plus sont supprimées, les doublons fusionnés et l’ensemble est compressé. Dans la zone de dialogue d’enregistrement, vous pouvez aussi choisir :

- **Keep only the characters each font uses:** supprime les parties des polices incorporées que le document n’utilise pas. Activé par défaut.
- **Images:** laissez les images telles quelles, ou réduisez-les à 300 ppp (pour l’impression) ou 150 ppp (pour la lecture à l’écran). Seules les images plus fines sont réduites. Les photos sont enregistrées en JPEG ; les schémas et captures d’écran restent sans perte. Les numérisations en noir et blanc ne sont pas modifiées.
- **Convert text to outlines:** dessine chaque lettre sous forme de tracé, pour que le document ait le même aspect sur les traceurs, les machines de découpe et les systèmes d’impression qui n’ont pas ses polices. Le texte de la copie ne peut plus être sélectionné, recherché ni copié.

Le gain de taille dépend du document. Ce sont les numérisations et les photos qui s’allègent le plus lorsque vous réduisez leurs images.

## Résumé des annotations

Choisissez File > Export Annotations Summary (⇧⌘E) pour enregistrer la liste des annotations du document, y compris celles d’autres apps, avec leurs auteurs, statuts et réponses. Par défaut, il s’agit d’un fichier Markdown. Donnez au fichier l’extension `.csv` pour enregistrer plutôt une feuille de calcul.

## Mesures

Pour exporter des mesures, utilisez le [tableau de métré](takeoff.md).

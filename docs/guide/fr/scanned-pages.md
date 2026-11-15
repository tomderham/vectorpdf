<!-- keywords: numérisation, numérisé, numérisée, numérisées, reconnaissance de texte, reconnaître le texte, OCR, sélectionner, copier, surligner, scan, scanned, scans, text recognition, recognize text, image, Run OCR, select, copy, highlight, PDF interrogeable, enregistrer le texte, calque de texte, langue, searchable PDF, save text, text layer, language -->
<!-- source: 8b77a345a44e -->

# Rechercher et sélectionner du texte dans des pages numérisées

Une page numérisée est une image de texte. VectorPDF peut reconnaître ce texte par reconnaissance optique de caractères (OCR), sur votre Mac, afin que vous puissiez y effectuer des recherches, le sélectionner et l’annoter.

## Fonctionnement

Lorsque vous ouvrez un document, VectorPDF cherche les pages numérisées parmi les 50 premières pages et reconnaît leur texte en arrière-plan. S’il reste des pages à traiter, l’onglet Search indique le nombre de pages numérisées trouvées.

- **Pour reconnaître toutes les pages numérisées trouvées,** cliquez sur **Run OCR** dans l’onglet Search.
- Une recherche les reconnaît aussi : vous pouvez donc simplement commencer à chercher.

Les surlignages suivent le texte, même si la page a été numérisée légèrement de travers.

Le texte est reconnu dans les langues des réglages Langue et région de votre Mac que la reconnaissance prend en charge, ou en anglais si elle n’en prend en charge aucune.

## Sélectionner le texte reconnu

Une fois une page reconnue, vous pouvez [sélectionner et copier](select-text.md) son texte, et le [surligner, le souligner ou le barrer](text-markup.md) comme sur n’importe quelle autre page. La reconnaissance peut prendre un moment, et les pages situées après les 50 premières nécessitent d’abord Run OCR ou une recherche.

La reconnaissance peut commettre des erreurs : vérifiez donc tout ce que vous copiez et qui doit être exact. Les sélections commencent et se terminent nettement aux bords des mots. À l’intérieur d’un mot, leurs extrémités sont approximatives.

> **Remarque :** Le texte reconnu est utilisé tant que le document est ouvert et n’est pas enregistré dans le PDF, sauf si vous choisissez de l’enregistrer (voir plus bas). Les annotations que vous ajoutez sont enregistrées. Si vous caviardez ou faites pivoter une page, son texte est reconnu à nouveau.

## Enregistrer le texte reconnu dans le PDF {#save-the-recognized-text-in-the-pdf}

Pour qu’un PDF numérisé soit aussi consultable par recherche dans d’autres apps, comme Aperçu, Spotlight et Acrobat, enregistrez-y le texte reconnu. Le texte est ajouté sous forme de calque invisible sous chaque page numérisée, à l’endroit où il a été reconnu : les pages restent identiques.

- **Pour l’enregistrer dans le document,** choisissez File > Save with Recognized Text, ou cliquez sur **Save in PDF** dans l’onglet Search une fois son texte reconnu. Vos autres modifications sont aussi enregistrées.
- **Pour l’enregistrer dans une copie,** choisissez File > Export Document As > Searchable PDF. Le document ouvert n’est pas modifié.

Dans les deux cas, VectorPDF reconnaît d’abord les pages numérisées qu’il n’a pas encore traitées, en affichant sa progression. Cela prend un moment pour chaque page. Vous pouvez cliquer sur Cancel : rien n’est alors enregistré.

Seules les pages sans texte propre reçoivent du texte. Une fois le texte dans le fichier, ces pages ne sont plus traitées comme numérisées : VectorPDF sélectionne et recherche le texte enregistré, comme les autres apps.

> **Important :** La reconnaissance peut faire des erreurs, et le texte enregistré suit le fichier partout : dans les index de recherche, le texte copié et les lecteurs d’écran. Vérifiez que le texte est correct avant de vous y fier, ou enregistrez plutôt une copie. L’enregistrement dans le document le rouvre aussi à partir du fichier : vous ne pouvez donc pas annuler les modifications faites avant l’enregistrement.

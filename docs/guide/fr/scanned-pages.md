<!-- keywords: numérisation, numérisé, numérisée, numérisées, reconnaissance de texte, reconnaître le texte, OCR, sélectionner, copier, surligner, scan, scanned, scans, text recognition, recognize text, image, Run OCR, select, copy, highlight -->
<!-- source: b7eac37a78fe -->

# Rechercher et sélectionner du texte dans des pages numérisées

Une page numérisée est une image de texte. VectorPDF peut reconnaître ce texte par reconnaissance optique de caractères (OCR), sur votre Mac, afin que vous puissiez y effectuer des recherches, le sélectionner et l’annoter.

## Fonctionnement

Lorsque vous ouvrez un document, VectorPDF cherche les pages numérisées parmi les 50 premières pages et reconnaît leur texte en arrière-plan. S’il reste des pages à traiter, l’onglet Search indique le nombre de pages numérisées trouvées.

- **Pour reconnaître toutes les pages numérisées trouvées,** cliquez sur **Run OCR** dans l’onglet Search.
- Une recherche les reconnaît aussi : vous pouvez donc simplement commencer à chercher.

Les surlignages suivent le texte, même si la page a été numérisée légèrement de travers.

## Sélectionner le texte reconnu

Une fois une page reconnue, vous pouvez [sélectionner et copier](select-text.md) son texte, et le [surligner, le souligner ou le barrer](text-markup.md) comme sur n’importe quelle autre page. La reconnaissance peut prendre un moment, et les pages situées après les 50 premières nécessitent d’abord Run OCR ou une recherche.

La reconnaissance peut commettre des erreurs : vérifiez donc tout ce que vous copiez et qui doit être exact. Les sélections commencent et se terminent nettement aux bords des mots. À l’intérieur d’un mot, leurs extrémités sont approximatives.

> **Remarque :** Le texte reconnu est utilisé tant que le document est ouvert et n’est pas enregistré dans le PDF. Les annotations que vous ajoutez sont enregistrées. Si vous caviardez ou faites pivoter une page, son texte est reconnu à nouveau.

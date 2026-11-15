<!-- keywords: onglet Document, champs de formulaire, champs, signatures, signé, signature numérique, certifié, liens, hyperliens, URL, liens web, destinations nommées, destinations, contenu, barre latérale, document tab, form fields, fields, signed, digital signature, certified, links, hyperlinks, web links, named destinations, contents, sidebar -->
<!-- source: e2c42440bfd7 -->

# Champs de formulaire, signatures, liens et destinations

L’onglet Document (une boîte), en haut de la barre latérale, répertorie ce qu’un document contient en plus de ses pages. Choisissez ce qu’il affiche dans le menu en haut de l’onglet :

- **Layers :** voir [Afficher et masquer les calques](layers.md).
- **Attachments :** voir [Fichiers joints à un PDF](attachments.md).
- **Form Fields :** chaque champ d’un formulaire, avec sa valeur, ainsi que ses signatures.
- **Links :** chaque lien, avec le texte sur lequel il se trouve et l’endroit où il mène.
- **Destinations :** les emplacements nommés du document vers lesquels des liens peuvent pointer.

Form Fields, Links et Destinations ne sont répertoriés que si vous activez **List form fields, links and destinations in the sidebar** dans VectorPDF > Settings > General. La plupart des documents contiennent des liens : sans cela, l’onglet apparaîtrait pour presque tous.

Le menu ne propose que ce que contient le document, et l’onglet n’apparaît que si celui-ci en contient au moins un.

## Champs de formulaire et signatures

Les champs sont répertoriés page par page, sous le nom que leur donne le formulaire. Chacun affiche sa valeur, et **Required** lorsque le formulaire indique qu’il doit être rempli. Maintenez le pointeur sur un champ pour voir son nom complet et son type. Cliquez sur un champ pour vous y rendre dans la page ; il est entouré un instant. Pour remplir des champs, voir [Remplir des formulaires](forms.md). La liste affiche les nouvelles valeurs pendant que vous tapez.

Un champ de signature indique qui l’a signé et quand, tel que la signature l’enregistre, ou **Not signed**. Il indique aussi si le fichier a été enregistré de nouveau après la signature, ce qui peut modifier ce qui a été signé, et si la signature certifie le document et quelles modifications elle autorise.

> **Remarque :** VectorPDF ne vérifie pas le certificat de la signature et ne peut donc pas vous dire si une signature est valide. Pour cela, utilisez un programme qui valide les signatures, comme Adobe Acrobat Reader.

## Liens

Les liens sont répertoriés page par page, dès que chaque page est lue : les premiers liens d’un long document s’affichent donc tout de suite. Utilisez les boutons au-dessus de la liste pour afficher **All** les liens, seulement les liens **Web** ou les liens **In Document**, et tapez dans **Filter** pour trouver un lien par son texte ou son adresse.

| Pour | Procédez ainsi |
| --- | --- |
| Afficher un lien sur sa page | Cliquez dessus |
| Suivre un lien | Double-cliquez dessus. Un lien web s’ouvre dans votre navigateur. |
| Copier une adresse web | Cliquez avec le bouton droit sur le lien, puis choisissez Copy Address |

## Destinations

Les destinations sont des emplacements nommés d’un document, comme `section.2` ou `figure.3`. LaTeX et d’autres programmes les créent pour que des liens puissent y pointer. Cliquez sur une destination pour vous y rendre. Pour copier son nom, cliquez dessus avec le bouton droit et choisissez Copy Name.

<!-- keywords: en-tête, en-têtes, pied de page, pieds de page, numéros de page, numérotation des pages, Bates, numéros Bates, numérotation Bates, filigrane, filigranes, BROUILLON, CONFIDENTIEL, juridique, header, headers, footer, footers, page numbers, page numbering, Bates numbers, Bates numbering, watermark, watermarks, DRAFT, CONFIDENTIAL, stamp text, legal, discovery, PDF -->
<!-- source: 7e05ab7492d9 -->

# En-têtes, pieds de page, numéros Bates et filigranes

Vous pouvez placer du texte en haut et en bas des pages, comme un titre, des numéros de page ou des numéros Bates, et un filigrane comme BROUILLON ou CONFIDENTIEL en travers. Choisissez Edit > Headers, Footers and Watermark, remplissez les parties souhaitées, puis cliquez sur **Add**.

VectorPDF conserve vos choix dans le document : vous pouvez donc modifier plus tard les en-têtes, les pieds de page et le filigrane, ou les retirer. Choisissez de nouveau Edit > Headers, Footers and Watermark, apportez vos modifications, puis cliquez sur **Update**. Pour tout retirer, cliquez sur **Remove All**.

Les modifications font partie du fichier lorsque vous l’[enregistrez](save.md).

## En-tête et pied de page

Saisissez du texte dans l’une des six cases : à gauche, au centre et à droite de l’en-tête et du pied de page. Laissez une case vide pour n’y rien placer.

Pour ajouter un numéro de page ou une autre valeur qui change d’une page à l’autre, cliquez dans une case, puis choisissez dans le menu **Insert** :

| Insert | Affiche |
| --- | --- |
| Page Number | Le numéro de la page, en comptant à partir de la première page marquée. Consultez [Pages et numéros](#pages-and-numbers). |
| Page Count | Le nombre de pages du document |
| Bates Number | Le numéro Bates de la page |
| Date | La date du jour |
| File Name | Le nom de fichier du document |

Chacun apparaît dans la case sous forme de mot entre doubles chevrons, comme `<<page>>`. Par exemple, saisissez `Page `, insérez Page Number, saisissez ` sur `, puis insérez Page Count pour obtenir « Page 3 sur 12 ».

Vous pouvez choisir la police, la taille et la couleur du texte, ainsi que les marges : la distance entre l’en-tête et le haut de la page, entre le pied de page et le bas, et entre les deux et les bords, en points (72 points font un pouce).

## Filigrane

Saisissez le texte du filigrane. Appuyez sur Retour pour une deuxième ligne. Choisissez ensuite :

- **Font** et **Color**.
- **As large as fits the page**, ou une taille de votre choix.
- **Opacity :** son intensité. Un filigrane léger laisse la page lisible.
- **Angle :** horizontal, diagonal ou vertical.
- **Behind the page's content :** dessine le filigrane sous le texte et les images de la page plutôt qu’au-dessus. Une page qui a un arrière-plan, comme une page numérisée, masque un filigrane placé derrière.

## Pages et numéros {#pages-and-numbers}

- **Pages :** toutes les pages, les pages impaires ou paires, et d’une page à une autre. Laissez From ou To vide pour la première ou la dernière page.
- **First page marked is page :** le numéro que Page Number donne à la première page marquée. Les numéros augmentent d’un pour chaque page marquée.
- **Bates numbers :** un préfixe, comme un nom d’affaire ou d’entreprise, le nombre de chiffres, le numéro de départ et un suffixe. Les numéros Bates augmentent d’un pour chaque page marquée et sont complétés par des zéros, comme ACME-000001. Insérez Bates Number dans un en-tête ou un pied de page pour les afficher.

## Bon à savoir

- Les en-têtes, pieds de page et filigranes font partie de la page, ce ne sont pas des [annotations](draw-and-notes.md) : ils sont donc imprimés et apparaissent dans d’autres apps. Ils sont marqués comme décoration de page, que les lecteurs d’écran peuvent ignorer. Vous pouvez rechercher et sélectionner leur texte.
- Les marges sont mesurées sur la page telle qu’elle est affichée : sur une page qui a été pivotée, l’en-tête reste donc en haut.
- VectorPDF ne peut modifier ou retirer que les en-têtes, pieds de page et filigranes qu’il a ajoutés. Ceux ajoutés par d’autres apps font partie du contenu de la page.
- Les ajouter à un document [signé numériquement](digital-signatures.md) modifie ce qui a été signé : ses signatures deviennent alors non valides.

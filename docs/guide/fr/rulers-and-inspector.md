<!-- keywords: barre d’état, position du pointeur, coordonnées, taille de page, format de papier, règles, repères, grille, aimantation, unités, millimètres, pouces, points, Inspector, police, taille de police, couleur, résolution d’image, navigateur, nombre de mots, nombre de caractères, status bar, pointer position, coordinates, page size, paper size, A4, Letter, ARCH, rulers, guides, grid, snap, units, millimeters, inches, font, font size, color, image resolution, dpi, ppi, line width, navigator, pan and zoom, word count, character count -->
<!-- source: f1f2dd215a95 -->

# Règles, barre d’état et Inspector

Ces outils indiquent où se trouvent les éléments d’une page et de quoi ils sont faits. Ils restent désactivés tant que vous ne les activez pas dans le menu View, pour que la lecture reste dégagée.

## La barre d’état

Choisissez View > Show Status Bar (⌘/) pour afficher une bande sous la page. Elle indique :

- **L’emplacement du pointeur** sur la page, depuis le coin supérieur gauche de la page. Sur une page dotée d’une [échelle de dessin](drawing-scale.md), elle indique aussi cet emplacement en unités réelles.
- **La taille de la page** sous le pointeur, ou de la page actuelle, avec le format de papier lorsqu’il correspond à l’un d’eux : A0 à A6, B3 à B5, Letter, Legal, Tabloid, ANSI C à E et ARCH A à E. Les jeux de plans mélangent souvent les formats, cette taille change donc d’une page à l’autre.
- **Une mesure pendant que vous la tracez :** sa longueur, son angle et sa distance à l’horizontale (ΔX) et à la verticale (ΔY) ; la longueur d’un périmètre jusqu’ici et son dernier segment ; une surface jusqu’ici et son périmètre. Voir [Mesurer des longueurs, des surfaces et des angles](measure.md).
- **La taille de la sélection de texte,** en mots et en caractères.

Choisissez les unités, Millimeters, Inches ou Points, dans le menu à droite de la barre d’état. Les règles, la grille et l’Inspector les utilisent aussi.

## Règles et repères

Choisissez View > Rulers and Grid > Show Rulers (⌘R) pour afficher des règles en haut et à gauche de la page. Elles mesurent la page sous le pointeur depuis son coin supérieur gauche, et un trait sur chaque règle indique où se trouve le pointeur.

| Pour | Procédez ainsi |
| --- | --- |
| Ajouter un repère | Faites glisser une règle sur la page |
| Déplacer un repère | Faites-le glisser |
| Supprimer un repère | Faites-le glisser hors de la page |
| Supprimer tous les repères | Choisissez View > Rulers and Grid > Clear Guides |

Les repères appartiennent à la page sur laquelle vous les placez. Ils restent tant que le document est ouvert et ne sont pas enregistrés dans celui-ci.

## La grille

Choisissez View > Rulers and Grid > Show Grid (⌘') pour tracer une grille sur chaque page, depuis son coin supérieur gauche. Choisissez son espacement dans View > Rulers and Grid > Grid Spacing. Une ligne sur cinq est plus foncée.

Lorsque **Snap to Guides and Grid** est activé dans View > Rulers and Grid, les points d’une mesure s’aimantent aux repères proches du pointeur, et à la grille tant qu’elle est affichée, comme ils s’aimantent aux angles avec Vertex Magnetic Snapping.

## L’Inspector {#the-inspector}

Choisissez View > Show Inspector (⌃⌘I) pour afficher l’Inspector à côté de la page. Vous pouvez aussi cliquer avec le bouton droit sur la page et choisir Inspect. Si vous avez [déplacé la recherche à droite](search.md#see-results-beside-the-outline), les deux partagent ce côté : passez de l’un à l’autre avec les boutons Search et Inspector en haut.

- **Texte, images et dessins :** avec l’Inspector ouvert, cliquez sur la page en mode Select. L’Inspector indique ce qui y est dessiné, et la page l’entoure :
  - **Texte :** la police, sa taille, le caractère, sa couleur et son espace colorimétrique, et si la police est incluse dans le fichier. Une police qui ne l’est pas est remplacée par une autre, dont le rendu imprimé peut différer.
  - **Images :** leur taille en pixels, leur résolution telle qu’elles sont placées sur la page, leur taille sur la page, leur espace colorimétrique et le nombre de bits par composante. Vérifiez la résolution d’une image avant d’imprimer ou d’optimiser.
  - **Dessins :** l’épaisseur et la couleur d’un trait, ou la couleur de remplissage d’une forme.
- **Annotations :** sélectionnez une annotation pour voir son type, son auteur, ses dates, son calque, son opacité et sa couleur. Pour la déplacer, tapez sa position (**X** et **Y**, depuis le coin supérieur gauche de la page) et appuyez sur Retour. Les rectangles, ovales, zones de texte, bulles, tampons et nuages de révision peuvent aussi être redimensionnés : tapez leurs **Width** et **Height**.

## Le navigateur

Choisissez View > Show Navigator (⌃⌘N) pour afficher, dans le coin de la fenêtre, une miniature de la page affichée. La partie visible à l’écran est entourée. Faites glisser le cadre, ou cliquez sur la miniature, pour vous déplacer sur une grande feuille à fort zoom.

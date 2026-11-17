<!-- keywords: dessiner, dessin, encre, stylo, main levée, forme, formes, rectangle, carré, ovale, cercle, ellipse, ligne, flèche, zone de texte, bulle, bulles, note, notes, pense-bête, commentaire, commentaires, réponse, réponses, statut, auteur, nuage de révision, nuage, extrémité de ligne, couleur, annuler, rétablir, annoter, annotation, annotations, gomme, draw, drawing, ink, pen, freehand, shape, shapes, rectangle, square, oval, circle, ellipse, line, arrow, text box, callout, callouts, note, notes, sticky note, comment, comments, reply, replies, status, author, revision cloud, cloud, line ending, color, colour, undo, redo, annotate, annotation, annotations, eraser, PDF, sélection multiple, plusieurs, aligner, répartir, groupe, select several, multiple, align, distribute, group -->
<!-- source: 7023d91b7100 -->

# Dessiner, ajouter des notes, du texte et des bulles

Appuyez sur ⇧⌘A ou cliquez sur le bouton Markup Toolbar pour afficher la barre d’outils Markup. Choisissez un outil, puis une couleur et une taille. Pour choisir une couleur, cliquez sur le bouton de couleur, vers la droite de la barre, puis sur une couleur.

Chaque outil a sa propre couleur et sa propre épaisseur de trait, et VectorPDF les mémorise. Au départ, le stylo et les formes sont rouges, les zones de texte et les légendes noires, et les notes jaunes. Choisir un outil désélectionne ce qui était sélectionné. Tant qu’un outil est utilisé, changer sa couleur ou son épaisseur modifie aussi ce qu’il vient de créer. Pour modifier une annotation faite plus tôt sans changer d’outil, sélectionnez-la avec l’outil Select, puis choisissez une couleur.

Pour terminer avec un outil, appuyez sur Escape, cliquez à nouveau sur l’outil ou choisissez Select, la flèche au début de la barre.

## Sélectionner et modifier des annotations {#select-and-change-annotations}

Choisissez **Select**, la flèche au début de la barre Markup ou de la barre Measurement. Avec Select, vous pouvez sélectionner du texte, ainsi que des annotations et des mesures :

- **Pointez sur l’une d’elles** : un contour en pointillés indique ce qu’un clic va prendre. Pour un rectangle, un ovale, un polygone ou un nuage, pointez sur son contour, et pour un dessin à main levée, sur son trait : ailleurs, un clic sélectionne le texte à cet endroit.
- **Cliquez dessus** pour la sélectionner. Faites-la ensuite glisser pour la déplacer, faites glisser une poignée pour la redimensionner ou la remodeler, utilisez les touches fléchées pour la décaler, choisissez une couleur ou une épaisseur dans la barre, ou appuyez sur Supprimer. Cliquez dessus avec le bouton droit pour ses commandes.
- **Sélectionner plusieurs annotations :** cliquez sur chacune en maintenant ⇧, ou maintenez ⌥ et faites glisser par-dessus pour sélectionner tout ce qui se trouve entièrement dans la zone. Choisissez Edit > Select All Annotations on Page (⌥⌘A) pour toutes les sélectionner. Consultez [Modifier plusieurs annotations à la fois](#change-several-annotations-at-once).

Tant qu’un outil de dessin ou de mesure est utilisé, un clic crée quelque chose de nouveau : choisissez donc d’abord Select, ou appuyez sur Escape.

## Dessiner à main levée

Choisissez l’outil stylo, réglez l’épaisseur du trait, puis faites glisser le pointeur sur la page. Choisissez une épaisseur en points dans la case d’épaisseur, ou saisissez-en une, de 0,1 à 72 points.

Pour déplacer un dessin, changer sa couleur ou son épaisseur, ou le supprimer, choisissez Select et cliquez sur son trait. Avec le stylo, un clic sur un dessin dessine par-dessus.

## Dessiner une forme

1. Choisissez l’outil Shapes, puis Rectangle, Oval, Line or Arrow, Revision Cloud, Polygon ou Polyline.
2. Réglez l’épaisseur du trait : choisissez une épaisseur en points, ou saisissez-en une. Pour une ligne ou une polyligne, utilisez le menu Line Ending pour choisir une pointe de flèche, comme Open Arrow, Closed Arrow ou Diamond, ou None pour une ligne simple.
3. Faites glisser sur la page. Un rectangle ou un ovale remplit la zone que vous parcourez. Une ligne va de l’endroit où vous commencez à celui où vous vous arrêtez, avec son extrémité à la fin.

Maintenez ⇧ enfoncée pendant le glissement pour dessiner un carré ou un cercle, ou pour garder une ligne à un multiple de 45°.

Pour un polygone ou une polyligne, cliquez sur chaque point au lieu de faire glisser. Cliquez à nouveau sur le premier point pour fermer un polygone, ou double-cliquez ou appuyez sur Retour pour terminer. Une polyligne reste ouverte et peut se terminer par une flèche. Appuyez sur Escape pour abandonner celle que vous tracez. Ortho Lock et le magnétisme de la barre Measurement s’appliquent à chaque point.

Un nuage de révision signale une zone modifiée ou à vérifier. Faites glisser autour de la zone : le nuage suit le contour que vous tracez. Un glissement rapide en ligne droite crée plutôt un nuage ovale.

Pour sélectionner, déplacer ou cliquer avec le bouton droit sur un rectangle, un ovale, un polygone ou un nuage, utilisez son contour : vous pouvez ainsi toujours sélectionner le texte à l’intérieur.

Pour modifier une ligne après l’avoir tracée, faites glisser l’une de ses extrémités pour ne déplacer que celle-ci, ou sélectionnez-la et choisissez une autre épaisseur ou extrémité dans la barre. Vous pouvez aussi cliquer dessus avec le bouton droit et choisir Line Ending. Sélectionnez un rectangle, un ovale, un polygone ou une polyligne et choisissez une épaisseur pour la modifier ; pour une polyligne, vous pouvez aussi changer son extrémité.

## Ajouter une zone de texte

1. Choisissez l’outil zone de texte et définissez une taille de police de 6 à 32 points.
2. Cliquez sur la page à l’endroit où vous voulez placer le texte, puis saisissez-le.
3. Cliquez en dehors de la zone ou appuyez sur Escape pour terminer.

Une zone de texte n’a ni bordure ni arrière-plan : le texte est posé directement sur la page, comme avec une machine à écrire. Acrobat et PDF-XChange la traitent comme du texte de machine à écrire.

Pour changer la taille de police plus tard, sélectionnez la zone de texte ou la légende, puis utilisez le curseur de taille de police de la barre Markup. Il y apparaît tant que l’une d’elles est sélectionnée.

## Ajouter une bulle

Une bulle est une note de texte dotée d’une flèche qui pointe vers un élément de la page.

1. Choisissez l’outil bulle.
2. Appuyez sur le point que la flèche doit toucher, puis faites glisser le pointeur jusqu’à l’endroit où vous voulez placer la note.
3. Saisissez votre note.

Vous pourrez ensuite faire glisser séparément la cible de la flèche et la note.

Pour choisir la terminaison de la ligne, par exemple une flèche ouverte, un losange ou une barre oblique, utilisez le menu Line Ending de la barre d’outils avant de dessiner. Pour modifier une bulle existante, cliquez dessus avec le bouton droit et choisissez Line Ending.

## Ajouter une note autocollante

Une note est une petite icône sur la page, associée à un commentaire.

1. Choisissez l’outil note autocollante.
2. Cliquez à l’endroit où vous voulez placer la note, puis saisissez votre texte.
3. Cliquez ailleurs pour terminer. Une note laissée vide est supprimée.

Double-cliquez sur une note pour la lire ou la modifier.

## Répondre à une annotation

Toute annotation peut recevoir des réponses : une note, un surlignage, un dessin, une forme, un nuage ou une mesure. Double-cliquez dessus, ou cliquez dessus avec le bouton droit et choisissez Comments…, pour voir qui l’a créée et quand. Cela fonctionne aussi pour les annotations d’autres personnes et d’autres apps. De là, vous pouvez :

- Saisir du texte dans le champ Reply et appuyer sur Return pour ajouter une réponse.
- Utiliser le menu Status pour la marquer comme Accepted, Rejected, Cancelled ou Completed.
- Cliquer sur le bouton de la corbeille pour la supprimer avec ses réponses.

Un double-clic sur une zone de texte ou une bulle modifie plutôt son texte ; cliquez dessus avec le bouton droit pour accéder à ses commentaires. Pour une ligne ou un dessin présent dans le fichier, cliquez aussi avec le bouton droit.

Votre nom sur les annotations provient du réglage Annotation Author dans [Réglages](settings.md).

## Afficher toutes les annotations {#see-all-annotations}

Cliquez sur l’onglet Comments de la barre latérale pour afficher toutes les annotations du document par page, avec leur commentaire, leur statut et leurs réponses. L’onglet apparaît dès que le document contient une annotation. Cliquez sur une annotation pour y accéder sur la page. Double-cliquez dessus pour y ouvrir ses commentaires, répondre ou changer son statut. Utilisez le bouton de filtre en haut pour n’afficher qu’un type, un auteur, un statut ou une date.

Pour obtenir un tableau que vous pouvez trier et filtrer dans une fenêtre plus grande, cliquez sur le bouton Annotations, à droite de la barre d’outils Markup. Sélectionnez-en une et cliquez sur Show on Page, ou double-cliquez dessus, pour accéder à sa page.

## Modifier une annotation

| Pour | Procédez ainsi |
| --- | --- |
| Modifier le texte | Double-cliquez sur une zone de texte ou une bulle, sélectionnez-la et appuyez sur Return, ou cliquez dessus avec le bouton droit et choisissez Edit Text Box ou Edit Callout Note |
| Déplacer | Faites-la glisser, ou sélectionnez-la et appuyez sur les touches fléchées. Maintenez la touche ⇧ enfoncée pour la déplacer de 10 points à la fois. |
| Redimensionner | Sélectionnez-la, puis faites glisser une poignée d’angle. Pour une ligne ou une flèche, faites glisser l’une de ses extrémités. |
| Supprimer | Sélectionnez-la et appuyez sur Delete, ou cliquez dessus avec le bouton droit et choisissez la commande de suppression, par exemple Delete Drawing ou Delete Text Box |

Utilisez l’outil Eraser de la barre d’outils Markup pour supprimer des annotations en cliquant dessus ou en faisant glisser le pointeur sur elles. La suppression d’une annotation supprime aussi ses réponses.

### Annotations d’autres personnes et d’autres apps

Vous pouvez modifier de la même façon les annotations déjà présentes dans le document, comme les formes, notes et nuages d’un autre relecteur :

- Faites glisser un rectangle, un ovale, un nuage, une ligne, une note, un tampon ou une zone de texte pour le déplacer, ou sélectionnez-le et appuyez sur les touches fléchées. Il garde son apparence, son auteur, sa date et ses réponses.
- Faites glisser une poignée d’angle d’un rectangle, d’un ovale ou d’un nuage pour le redimensionner, ou l’une des extrémités d’une ligne pour déplacer cette extrémité.
- Sélectionnez-en une et choisissez une couleur, une épaisseur ou une extrémité de ligne dans la barre d’outils Markup pour la modifier. VectorPDF la redessine alors dans son propre style.

Les surlignages, soulignements, barrés, dessins à main levée et mesures du fichier restent en place, comme les vôtres, mais vous pouvez les supprimer ou y répondre. Vous ne pouvez pas modifier le texte d’une zone de texte créée dans une autre app.

## Modifier plusieurs annotations à la fois {#change-several-annotations-at-once}

Avec l’outil Select, sélectionnez une annotation, puis cliquez sur d’autres de la même page en maintenant ⇧ pour les ajouter ; cliquez à nouveau sur l’une d’elles avec ⇧ pour la retirer. Ou maintenez ⌥ et faites glisser par-dessus, ou choisissez Edit > Select All Annotations on Page (⌥⌘A). Ensuite :

- **Les déplacer :** faites glisser l’une d’elles, ou utilisez les touches fléchées.
- **Changer leur couleur ou leur épaisseur :** choisissez-la dans la barre.
- **Les aligner :** cliquez avec le bouton droit sur l’une d’elles et choisissez Align, puis un bord ou un centre. Avec trois ou plus, Distribute Horizontally ou Distribute Vertically les espace uniformément.
- **Les supprimer :** appuyez sur Supprimer, ou cliquez avec le bouton droit sur l’une d’elles et choisissez Delete, qui indique combien.

Chacune de ces actions est une seule étape pour Undo. Cliquez n’importe où ailleurs pour n’en sélectionner à nouveau qu’une.

## Annuler une modification

Choisissez Edit > Undo, ou appuyez sur ⌘Z, pour annuler l’ajout, le déplacement, le changement de style ou la suppression d’une annotation. Appuyez sur ⇧⌘Z pour rétablir. Cela fonctionne pour toute annotation, y compris une annotation déjà présente dans le document que vous avez supprimée ou effacée par erreur avec la gomme. Elle revient avec ses réponses, son auteur et sa date.

Vos annotations sont stockées dans le PDF sous forme d’annotations standard lorsque vous [enregistrez](save.md) : elles apparaissent donc dans les autres apps PDF, avec leurs auteurs, réponses et statuts. Pour les intégrer définitivement à la page, [exportez un PDF aplati](export.md#flattened-pdf).

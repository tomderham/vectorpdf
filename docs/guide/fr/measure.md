<!-- keywords: mesurer, mesure, mesures, longueur, cote, périmètre, surface, aire, orthogonal, magnétisme, accrochage, measure, measurement, measurements, length, distance, dimension, perimeter, area, angle, ortho, snap, snapping, modifier, déplacer, poignée, décalage, edit, change, move, reshape, handle, offset, compter, comptage, décompte, symboles, count, counting, tally, symbols -->
<!-- source: 105c5177cf19 -->

# Mesurer des longueurs, des surfaces et des angles, et compter

Appuyez sur ⇧⌘M pour afficher la barre d’outils Measurement. Si votre plan est à l’échelle, [définissez d’abord l’échelle](drawing-scale.md).

Pour plus de précision, zoomez avant de mesurer. Appuyez sur Escape pour annuler une mesure en cours. Appuyez à nouveau sur Escape, ou cliquez sur l’outil sélectionné, pour poser l’outil.

## Outils de mesure

| Outil | Utilisation |
| --- | --- |
| Linear Dimension | Faites glisser le pointeur d’un point à l’autre. |
| Perimeter | Cliquez sur chaque point du tracé. Appuyez sur Return ou double-cliquez pour terminer. |
| Polygon Area | Cliquez sur chaque angle. Appuyez sur Return, double-cliquez ou cliquez sur le premier point pour fermer la forme. |
| Vertex Angle | Cliquez sur un point de la première ligne, puis sur le sommet, puis sur un point de la seconde ligne. |
| Count | Saisissez ce que vous comptez dans la case de groupe, par exemple Prises, puis cliquez sur chacun. |

## Compter des éléments sur un plan {#count-things-on-a-drawing}

Choisissez l’outil Count, puis saisissez un nom de groupe dans la case à côté, par exemple Prises ou Portes type A, ou choisissez un groupe déjà présent dans le document dans le menu à côté de la case. Chaque clic place un marqueur, un point de la couleur de la barre Measurement, et la barre indique combien d’éléments de ce groupe se trouvent sur la page. Changez le nom du groupe pour compter autre chose ; chaque groupe est compté à part. Utilisez une couleur différente pour chaque groupe afin de les distinguer sur la page.

Pour déplacer un marqueur, faites-le glisser avec l’outil Select. Pour en supprimer un, cliquez dessus avec le bouton droit et choisissez Delete Count Marker. Le [tableau de métré](takeoff.md) indique combien il y en a de chaque groupe sur chaque page, avec des totaux. Les marqueurs sont enregistrés dans le PDF sous forme de petits cercles, que les autres apps affichent aussi.

## Dessiner avec précision

- **Ortho Lock** maintient les lignes à 0°, 45° et 90°. Maintenez la touche ⇧ enfoncée pour l’inverser le temps d’une ligne : pour mesurer selon n’importe quel angle lorsqu’il est activé, ou pour garder une ligne droite lorsqu’il est désactivé.
- **Vertex Magnetic Snapping** aimante le pointeur aux angles et aux extrémités du plan.
- **Repères et grille :** lorsque View > Rulers and Grid > Snap to Guides and Grid est activé, les points s’aimantent aux repères que vous avez tirés des règles, et à la grille tant qu’elle est affichée. Voir [Règles, barre d’état et Inspector](rulers-and-inspector.md).
- **La barre d’état** (View > Show Status Bar) affiche davantage d’informations sur une mesure pendant que vous la tracez que son étiquette : son angle et sa distance à l’horizontale et à la verticale, ou le périmètre d’une surface jusqu’ici.

## Modifier une mesure

Choisissez **Select**, la flèche au début de la barre Measurement, ou appuyez sur Escape pour poser l’outil de mesure. Pointez sur une mesure : un contour en pointillés l’indique ; cliquez dessus pour la sélectionner. Cliquez avec ⇧ pour en sélectionner plusieurs, ou maintenez ⌥ et faites glisser par-dessus. Avec un outil de mesure en cours d’utilisation, un clic mesure à nouveau.

Une mesure sélectionnée a des poignées sur ses points.

| Pour | Procédez ainsi |
| --- | --- |
| Déplacer un point | Faites glisser sa poignée. Ortho Lock et le magnétisme fonctionnent comme lorsque vous mesurez. |
| Déplacer toute la mesure | Faites glisser sa ligne, ou appuyez sur les touches fléchées (⇧ la déplace de 10 points). |
| Rapprocher ou éloigner une ligne de cote de ce qu’elle mesure | Faites glisser son libellé, ou la ligne de cote elle-même une fois qu’elle est écartée des points. |
| Changer sa couleur | Choisissez une couleur avec le bouton de couleur de la barre d’outils Measurement. |
| Modifier son épaisseur de trait | Choisissez ou saisissez une épaisseur dans la case d’épaisseur de la barre Measurement. |

La valeur est recalculée pendant que vous faites glisser. Faites glisser au-delà du bord de la fenêtre pour faire défiler, pour une mesure plus longue que la vue. Choisissez Edit > Undo pour rétablir une mesure telle qu’elle était. Les mesures déjà enregistrées dans le PDF peuvent aussi être modifiées.

Pour sélectionner une surface, cliquez sur son bord : un clic à l’intérieur sélectionne le texte qui s’y trouve.

## Modifier l’apparence des mesures

Utilisez le bouton de couleur et la case d’épaisseur de la barre d’outils Measurement avant de mesurer. Choisissez une épaisseur en points, ou saisissez-en une, de 0,1 à 72 points. Les nouvelles mesures sont grises, de 1,5 point d’épaisseur, tant que vous ne choisissez pas autre chose. VectorPDF mémorise votre choix, et la barre Markup garde ses propres couleurs et épaisseurs. Pour changer la couleur ou l’épaisseur d’une mesure déjà faite, sélectionnez-la, puis choisissez une couleur ou une épaisseur dans la barre Measurement. L’épaisseur est enregistrée dans le PDF.

## Conserver ou supprimer des mesures

Les mesures sont des annotations, enregistrées dans le PDF lorsque vous [enregistrez](save.md). Pour en supprimer une, cliquez dessus avec le bouton droit, puis choisissez la commande de suppression, comme Delete Dimension, Delete Area Takeoff ou Delete Count Marker.

Pour obtenir la liste de toutes vos mesures, consultez le [tableau de métré](takeoff.md).

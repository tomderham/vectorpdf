<!-- keywords: mesurer, mesure, mesures, longueur, cote, périmètre, surface, aire, orthogonal, magnétisme, accrochage, measure, measurement, measurements, length, distance, dimension, perimeter, area, angle, ortho, snap, snapping, modifier, déplacer, poignée, décalage, edit, change, move, reshape, handle, offset -->
<!-- source: ce12181269d9 -->

# Mesurer des longueurs, des surfaces et des angles

Appuyez sur ⇧⌘M pour afficher la barre d’outils Measurement. Si votre plan est à l’échelle, [définissez d’abord l’échelle](drawing-scale.md).

Pour plus de précision, zoomez avant de mesurer. Appuyez sur Escape pour annuler une mesure en cours. Appuyez à nouveau sur Escape, ou cliquez sur l’outil sélectionné, pour poser l’outil.

## Outils de mesure

| Outil | Utilisation |
| --- | --- |
| Linear Dimension | Faites glisser le pointeur d’un point à l’autre. |
| Perimeter | Cliquez sur chaque point du tracé. Appuyez sur Return ou double-cliquez pour terminer. |
| Polygon Area | Cliquez sur chaque angle. Appuyez sur Return, double-cliquez ou cliquez sur le premier point pour fermer la forme. |
| Vertex Angle | Cliquez sur un point de la première ligne, puis sur le sommet, puis sur un point de la seconde ligne. |

## Dessiner avec précision

- **Ortho Lock** maintient les lignes à 0°, 45° et 90°. Maintenez la touche ⇧ enfoncée pour l’inverser le temps d’une ligne : pour mesurer selon n’importe quel angle lorsqu’il est activé, ou pour garder une ligne droite lorsqu’il est désactivé.
- **Vertex Magnetic Snapping** aimante le pointeur aux angles et aux extrémités du plan.

## Modifier une mesure

Appuyez sur Escape, ou cliquez sur l’outil sélectionné, pour poser l’outil de mesure, puis cliquez sur une mesure pour la sélectionner. Des poignées apparaissent sur ses points.

| Pour | Procédez ainsi |
| --- | --- |
| Déplacer un point | Faites glisser sa poignée. Ortho Lock et le magnétisme fonctionnent comme lorsque vous mesurez. |
| Déplacer toute la mesure | Faites glisser sa ligne, ou appuyez sur les touches fléchées (⇧ la déplace de 10 points). |
| Rapprocher ou éloigner une ligne de cote de ce qu’elle mesure | Faites glisser son libellé, ou la ligne de cote elle-même une fois qu’elle est écartée des points. |
| Changer sa couleur | Choisissez une couleur avec le bouton de couleur de la barre d’outils Measurement. |

La valeur est recalculée pendant que vous faites glisser. Choisissez Edit > Undo pour rétablir une mesure telle qu’elle était. Les mesures déjà enregistrées dans le PDF peuvent aussi être modifiées.

Pour sélectionner une surface, cliquez sur son bord : un clic à l’intérieur sélectionne le texte qui s’y trouve.

## Modifier l’apparence des mesures

Utilisez le bouton de couleur et l’épaisseur de trait de la barre d’outils Measurement avant de mesurer. Pour changer la couleur d’une mesure déjà créée, sélectionnez-la, puis choisissez une couleur.

## Conserver ou supprimer des mesures

Les mesures sont des annotations, stockées dans le PDF lorsque vous [enregistrez](save.md). Pour en supprimer une, cliquez dessus avec le bouton droit, puis choisissez la commande de suppression, par exemple Delete Dimension ou Delete Area Takeoff.

Pour obtenir la liste de toutes vos mesures, consultez le [tableau de métré](takeoff.md).

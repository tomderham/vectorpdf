<!-- keywords: calques, calque, contenu facultatif, CAO, plans, dessins, afficher, masquer, visibilité, annotations, nouveau calque, renommer un calque, supprimer un calque, layers, layer, optional content, OCG, CAD, AutoCAD, Revit, show, hide, visibility, markups, annotations, new layer, rename layer, delete layer -->
<!-- source: 0a0a671f9044 -->

# Afficher et masquer les calques

Les plans exportés depuis des logiciels de CAO et de conception placent souvent chaque partie d’une feuille sur son propre calque : murs, électricité, plomberie, cotes, nuages de révision. Vous pouvez afficher ou masquer chacun d’eux.

L’onglet Layers n’apparaît en haut de la barre latérale que si le document contient des calques. Pour donner un premier calque à un document, consultez [Ajouter, renommer et supprimer des calques](#add-rename-and-delete-layers).

- **Afficher ou masquer un calque :** cochez ou décochez sa case. La page est redessinée immédiatement.
- **Choisir un calque dans un groupe :** certains documents regroupent des calques pour qu’un seul s’affiche à la fois, comme les langues ou les échelles d’une feuille. Ils ont des boutons ronds ; en choisir un masque les autres.
- **Titres :** ils regroupent les calques listés en dessous et ne peuvent pas être masqués eux-mêmes.
- **Calques verrouillés :** ils ont un cadenas à côté. Le document ne permet pas de les afficher ou de les masquer.

Les calques que vous masquez sont aussi exclus quand vous [imprimez](print.md), [sélectionnez du texte](select-text.md) ou [effectuez une recherche](search.md) : vous ne travaillez qu’avec ce que vous voyez.

## Placer des annotations sur un calque

Les annotations peuvent aussi se trouver sur un calque : elles s’affichent et se masquent alors avec lui. Les autres apps qui lisent les calques, comme Acrobat et Bluebeam, les affichent et les masquent de la même façon.

- **Choisir où vont les nouvelles annotations :** dans la [barre d’outils Markup](draw-and-notes.md) ou la [barre d’outils Measurement](measure.md), cliquez sur le menu des calques (il indique **No Layer** tant que vous n’en avez pas choisi) et choisissez un calque. Tout ce que vous créez ensuite y est placé, jusqu’à ce que vous choisissiez un autre calque ou **No Layer**. Vous pouvez aussi cliquer avec le bouton droit sur un calque dans l’onglet Layers et choisir **Put New Annotations Here**. Le calque des nouvelles annotations est signalé par un crayon.
- **Déplacer une annotation vers un autre calque :** cliquez dessus avec le bouton droit et choisissez **Layer**, puis un calque, ou **None** pour la retirer de tout calque.
- **Ajouter votre propre calque :** consultez [Ajouter, renommer et supprimer des calques](#add-rename-and-delete-layers).

Le menu des calques n’apparaît que si un document contient des calques : les barres d’outils des autres documents ne changent pas.

Les annotations d’un calque masqué disparaissent de la page, de l’[onglet Comments](draw-and-notes.md#see-all-annotations) et du [tableau des métrés](takeoff.md), et ne peuvent être ni sélectionnées ni effacées. Le tableau Annotations les liste toujours, avec leur calque.

Si vous choisissez un calque masqué pour les nouvelles annotations, il est affiché, pour que ce que vous créez ne disparaisse pas. Undo replace une annotation sur le calque où elle se trouvait.

## Ajouter, renommer et supprimer des calques {#add-rename-and-delete-layers}

Les relecteurs placent souvent leurs annotations sur leurs propres calques, par exemple un par corps de métier ou par cycle de relecture, même sur des plans livrés sans calques. Chacune de ces commandes modifie le document, et Undo l’annule.

- **Ajouter un calque :** choisissez Edit > New Layer…, puis nommez-le. Cela fonctionne dans tout PDF : c’est ainsi qu’un document reçoit son premier calque ; l’onglet Layers et les menus des calques apparaissent alors. Les nouvelles annotations vont sur le nouveau calque. Dans un document qui a déjà des calques, vous pouvez aussi cliquer sur **+** en haut de l’onglet Layers, ou choisir **New Layer…** dans le menu des calques.
- **Renommer un calque :** choisissez Edit > Rename Layer…, choisissez le calque, puis saisissez son nouveau nom.
- **Supprimer un calque :** choisissez Edit > Delete Layer…, puis le calque. Ses annotations restent sur la page, sans calque. Seuls les calques qui ne contiennent que des annotations peuvent être supprimés : supprimer un calque sur lequel se trouve le plan lui-même laisserait cette partie du plan toujours affichée ; ces calques ne sont donc pas listés.

## Ce qui est enregistré

Les calques que vous ajoutez, renommez ou supprimez sont enregistrés avec le document, tout comme les calques sur lesquels se trouvent les annotations.

Les calques affichés ne sont pas enregistrés avec le document. La prochaine fois que vous l’ouvrirez, ses calques seront affichés comme le document lui-même l’indique, et toute personne à qui vous l’envoyez verra la même chose.

> **Remarque :** Un document d’une ou deux pages contenant des calques s’ouvre sur l’onglet Layers, sauf si vous avez masqué la barre latérale pour ce document. Utilisez le bouton de barre latérale dans la barre d’outils pour l’afficher.

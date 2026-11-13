<!-- keywords: calques, calque, contenu facultatif, CAO, plans, dessins, afficher, masquer, visibilité, annotations, nouveau calque, renommer un calque, supprimer un calque, configuration de calques, configurations, états des calques, traçage, layers, layer, optional content, OCG, CAD, AutoCAD, Revit, show, hide, visibility, markups, annotations, new layer, rename layer, delete layer, layer configuration, configurations, layer states, plot -->
<!-- source: 2395c1338d37 -->

# Afficher et masquer les calques

Les plans exportés depuis des logiciels de CAO et de conception placent souvent chaque partie d’une feuille sur son propre calque : murs, électricité, plomberie, cotes, nuages de révision. Vous pouvez afficher ou masquer chacun d’eux.

Les calques se trouvent dans l’onglet Document (une boîte) en haut de la barre latérale, qui apparaît lorsque le document contient des calques ou d’autres éléments qu’il répertorie. Si l’onglet affiche autre chose, choisissez **Layers** dans le menu en haut de celui-ci. Pour donner un premier calque à un document, consultez [Ajouter, renommer et supprimer des calques](#add-rename-and-delete-layers).

- **Afficher ou masquer un calque :** cochez ou décochez sa case. La page est redessinée immédiatement.
- **Choisir un calque dans un groupe :** certains documents regroupent des calques pour qu’un seul s’affiche à la fois, comme les langues ou les échelles d’une feuille. Ils ont des boutons ronds ; en choisir un masque les autres.
- **Titres :** ils regroupent les calques listés en dessous et ne peuvent pas être masqués eux-mêmes.
- **Calques verrouillés :** ils ont un cadenas à côté. Le document ne permet pas de les afficher ou de les masquer.

Les calques que vous masquez sont aussi exclus quand vous [imprimez](print.md), [sélectionnez du texte](select-text.md), [effectuez une recherche](search.md), [exportez un PDF aplati](export.md#flattened-pdf) ou [interrogez l’Agent](agent.md) : vous ne travaillez qu’avec ce que vous voyez.

## Choisir une configuration de calques

Certains documents proposent plusieurs façons d’afficher leurs calques, par exemple une pour le traçage, une par corps de métier ou une par langue. Dans ceux-ci, le haut de la liste des calques indique la configuration utilisée, à la place du nombre de calques. Il s’agit de **Default** jusqu’à ce que vous en choisissiez une autre, sauf si le document nomme sa configuration par défaut.

Cliquez dessus, puis choisissez une configuration. Ses calques sont affichés et masqués comme elle l’indique, et listés comme elle les liste.

Si vous affichez ou masquez ensuite un calque, **(Changed)** apparaît après le nom de la configuration. Choisissez à nouveau la configuration pour rétablir ses calques.

## Placer des annotations sur un calque

Les annotations peuvent aussi se trouver sur un calque : elles s’affichent et se masquent alors avec lui. Les autres apps qui lisent les calques, comme Acrobat et Bluebeam, les affichent et les masquent de la même façon.

- **Choisir où vont les nouvelles annotations :** dans la [barre d’outils Markup](draw-and-notes.md) ou la [barre d’outils Measurement](measure.md), cliquez sur le menu des calques (il indique **No Layer** tant que vous n’en avez pas choisi) et choisissez un calque. Tout ce que vous créez ensuite va sur ce calque, jusqu’à ce que vous choisissiez un autre calque ou **No Layer**. Vous pouvez aussi cliquer avec le bouton droit sur un calque dans l’onglet Document et choisir **Put New Annotations Here**. Le calque qui reçoit les nouvelles annotations est accompagné d’un crayon.
- **Déplacer une annotation vers un autre calque :** cliquez dessus avec le bouton droit et choisissez **Layer**, puis un calque, ou **None** pour la retirer de tout calque.
- **Ajouter votre propre calque :** consultez [Ajouter, renommer et supprimer des calques](#add-rename-and-delete-layers).

Le menu des calques n’apparaît que si un document contient des calques : les barres d’outils des autres documents ne changent pas.

Les annotations d’un calque masqué disparaissent de la page, de l’[onglet Comments](draw-and-notes.md#see-all-annotations) et du [tableau des métrés](takeoff.md), et ne peuvent être ni sélectionnées ni effacées. Le tableau Annotations les liste toujours, avec leur calque.

Si vous choisissez un calque masqué pour les nouvelles annotations, il est affiché, pour que ce que vous créez ne disparaisse pas. Undo replace une annotation sur le calque où elle se trouvait.

## Ajouter, renommer et supprimer des calques {#add-rename-and-delete-layers}

Les relecteurs placent souvent leurs annotations sur leurs propres calques, par exemple un par corps de métier ou par cycle de relecture, même sur des plans livrés sans calques. Chacune de ces commandes modifie le document, et Undo l’annule.

- **Ajouter un calque :** choisissez Edit > New Layer…, puis nommez-le. Cela fonctionne dans n’importe quel PDF : c’est ainsi qu’un document reçoit son premier calque ; les calques de l’onglet Document et les menus des calques apparaissent alors. Les nouvelles annotations vont sur le nouveau calque. Dans un document qui contient déjà des calques, vous pouvez aussi cliquer sur **+** au-dessus de la liste des calques, ou choisir **New Layer…** dans le menu des calques.
- **Renommer un calque :** choisissez Edit > Rename Layer…, choisissez le calque, puis saisissez son nouveau nom.
- **Supprimer un calque :** choisissez Edit > Delete Layer…, puis le calque. Ses annotations restent sur la page, sans calque. Seuls les calques qui ne contiennent que des annotations peuvent être supprimés : supprimer un calque sur lequel se trouve le plan lui-même laisserait cette partie du plan toujours affichée ; ces calques ne sont donc pas listés.

## Ce qui est enregistré

Les calques que vous ajoutez, renommez ou supprimez sont enregistrés avec le document, tout comme les calques sur lesquels se trouvent les annotations.

Les calques affichés et la configuration choisie ne sont pas enregistrés avec le document. La prochaine fois que vous l’ouvrirez, ses calques seront affichés comme le document lui-même l’indique, et toute personne à qui vous l’envoyez verra la même chose.

> **Remarque :** Un document d’une ou deux pages contenant des calques s’ouvre sur ses calques dans l’onglet Document, sauf si vous avez masqué la barre latérale pour ce document. Utilisez le bouton de la barre latérale dans la barre d’outils pour l’afficher.

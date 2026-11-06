<!-- keywords: comparer, comparaison, différences, révision, versions, modifications, côte à côte, défilement synchronisé, renumérotation, numéros de page, renvois, table des matières, compare, comparison, diff, difference, differences, revision, revisions, redline, changes, versions, side by side, synchronized scrolling, scroll together, renumbering, page numbers, cross-references, table of contents -->
<!-- source: 84d22a753af8 -->

# Comparer deux documents

Compare Documents affiche deux versions d’un document côte à côte, en surlignant dans les deux le texte qui a changé. Lorsque vous faites défiler l’une, l’autre défile jusqu’au même texte, même là où des pages ont été ajoutées ou supprimées d’une version à l’autre.

## Ouvrir une comparaison

1. Choisissez File > Compare Documents.
2. Choisissez le document d’origine (Original) et le document révisé (Revised). Chaque menu liste les documents ouverts ; choisissez Choose File pour en sélectionner un autre. Le document au premier plan est d’abord l’original. Cliquez sur Swap pour les échanger.
3. Cliquez sur Compare.

Vous pouvez aussi cliquer avec le bouton droit sur le titre du document, ou sur une partie vide de la barre d’outils, et choisir un document dans Compare With. Le document au premier plan est alors comparé à celui que vous choisissez.

La comparaison s’ouvre dans un nouvel onglet, avec l’original à gauche et la révision à droite. Les deux y sont en lecture seule. Pour modifier l’un d’eux, ouvrez-le dans son propre onglet.

## Lire les modifications

- Les mots supprimés de l’original sont surlignés en rouge, à gauche.
- Les mots ajoutés dans la révision sont surlignés en vert, à droite.
- Là où du texte n’a été ajouté que d’un côté, une fine barre de l’autre côté indique où il se trouverait.
- Le texte identique dans les deux, mais placé ailleurs, est souligné en bleu des deux côtés, par exemple un tableau qui tombe de l’autre côté d’un saut de page, ou une clause déplacée. Il faut au moins dix mots à la suite. Le texte déplacé ne compte pas comme une modification ; le haut de l’onglet Changes indique combien de passages sont ailleurs.

L’onglet Changes de la barre latérale liste chaque modification : les mots supprimés barrés en rouge, les mots ajoutés en vert, et le numéro de page dans la révision. Cliquez sur une modification pour y aller dans les deux documents.

Pour parcourir les modifications, cliquez sur la flèche vers le haut ou vers le bas en haut de l’onglet Changes, choisissez Go > Previous Change ou Go > Next Change, ou appuyez sur ⌥⌘Up Arrow ou ⌥⌘Down Arrow. L’onglet indique la modification où vous êtes, par exemple 3 of 12. Cette modification est surlignée plus fortement et sélectionnée dans la liste.

Seul le texte est comparé. Les modifications de mise en forme, d’images ou de dessins ne sont pas affichées. Les en-têtes, pieds de page et numéros de page sont ignorés, pour qu’ils n’apparaissent pas comme des modifications quand les pages se décalent.

## Trouver une section ou un mot

Les onglets Outline & Thumbnails et Search de la barre latérale portent sur la révision, comme dans tout onglet. Allez à une section ou à un résultat de recherche, et l’original suit jusqu’au même texte.

## Défiler et zoomer ensemble

La ligne située à environ un tiers de la hauteur de chaque côté montre le même texte. Quand un côté contient du texte absent de l’autre, l’autre attend que vous l’ayez dépassé. Vous pouvez faire défiler l’un ou l’autre côté ; l’autre suit.

Zoomer d’un côté zoome les deux, et le texte que vous lisez reste à sa place. Au-delà de la largeur de la page, faire défiler un côté horizontalement fait aussi défiler l’autre, pour que les deux montrent la même partie de la page.

## Options de comparaison

En haut de l’onglet Changes, choisissez Ignore Case ou Ignore Punctuation pour ignorer les différences de majuscules ou de ponctuation. Les guillemets typographiques et droits, ainsi que les différents types de tirets, sont toujours considérés comme identiques.

### Ignorer la renumérotation

Quand une clause, une figure ou un tableau est ajouté ou supprimé, tout ce qui suit est renuméroté, et chaque numéro de page suivant change. Dans un long document, la plupart des modifications peuvent être de nouveaux numéros dans la table des matières, la liste des figures et les renvois. Ignore Renumbering, activé dès le départ, les ignore :

- Une entrée de la table des matières ou d’une liste des figures, ou un renvoi comme « voir 9.4.2.18 », n’est pas considéré comme modifié s’il pointe vers le même endroit dans les deux versions, même si son numéro ou son numéro de page est nouveau.
- À l’endroit vers lequel il pointe, le numéro du titre ou de la légende n’est pas non plus considéré comme modifié s’il a changé de la même façon. Par exemple, « Figure 9-806 » qui devient « Figure 9-809 ».

Ce qui compte comme le même endroit vient des liens des documents, et non de l’aspect des numéros. Un renvoi qui pointe désormais ailleurs apparaît toujours comme une modification, tout comme un numéro qui ne fait pas partie d’un lien, par exemple « Table 9-12 » saisi en texte simple. Un titre reformulé apparaît toujours comme modifié au niveau du titre lui-même, même si son entrée dans la table des matières ne l’est pas.

Ignore Renumbering nécessite des documents contenant des liens internes, que la plupart des traitements de texte et des apps de mise en page créent pour la table des matières et les renvois. L’option n’est pas disponible si aucun des documents n’en contient. Un PDF réenregistré par une app qui supprime les liens n’en a pas, même si l’original en avait.

Pour voir tous les numéros qui ont changé, désactivez Ignore Renumbering.

## Si la comparaison n’est pas utile

- **Un document n’a pas de texte à comparer :** les pages numérisées n’ont pas de texte tant qu’il n’a pas été reconnu. Consultez [Rechercher et sélectionner du texte dans des pages numérisées](scanned-pages.md).
- **Ces documents ont peu de texte en commun :** il ne s’agit peut-être pas de versions du même document.

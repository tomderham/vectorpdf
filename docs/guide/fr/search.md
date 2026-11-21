<!-- keywords: rechercher, recherche, trouver, résultat suivant, casse, mot entier, recherche intelligente, motifs ignorés, expression régulière, balises, recherches récentes, historique de recherche, section, plan, table des matières, côté droit, à côté du plan, déplacer la recherche, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, recent searches, search history, section, outline, table of contents, right side, beside the outline, move search, PDF -->
<!-- source: 9e3d931100aa -->

# Rechercher dans un document

## Trouver du texte

1. Appuyez sur ⌘F. VectorPDF affiche l’onglet Search dans la barre latérale, ou à droite de la fenêtre si vous l’y avez [déplacé](#see-results-beside-the-outline).
2. Saisissez ce que vous cherchez. Les résultats apparaissent au fur et à mesure, à partir de la page où vous êtes.

Les résultats sont listés par page, chacun avec le texte qui l’entoure, et chaque occurrence est surlignée dans le document. Dans un document doté d’un [plan](outline-and-thumbnails.md), les résultats sont aussi regroupés par section. Le nom de la section reste en haut de la liste pendant que vous faites défiler ses résultats. Pour voir de quelles sections plus larges elle fait partie, placez le pointeur dessus.

## Passer d’un résultat à l’autre

| Pour | Procédez ainsi |
| --- | --- |
| Passer au résultat suivant | Appuyez sur Return ou ⌘G, ou cliquez sur la flèche vers le bas |
| Passer au résultat précédent | Appuyez sur ⇧Return ou ⇧⌘G, ou cliquez sur la flèche vers le haut |
| Accéder à n’importe quel résultat | Cliquez dessus |
| Parcourir la liste | Cliquez sur un résultat, puis appuyez sur les touches fléchées |

Cliquez avec le bouton droit sur un résultat pour [créer une ancre](anchors.md) à partir de celui-ci ou l’ouvrir dans une nouvelle fenêtre.

## Voir les résultats à côté du plan {#see-results-beside-the-outline}

Pour voir les résultats et le plan en même temps, cliquez sur le bouton d’options à côté du champ de recherche et choisissez Show Search on Right. La recherche passe sur le côté droit de la fenêtre et la barre latérale affiche le plan, ou les vignettes des pages si le document n’a pas de plan. Chaque entrée du plan qui contient des résultats indique combien elle en a, et le nombre de la section du résultat actuel est mis en évidence. Une section dont les sous-sections sont masquées compte aussi leurs résultats. Cliquez sur une entrée du plan : la liste des résultats défile jusqu’aux résultats de cette section (ou de ses sous-sections, si elle n’en a aucun elle-même), tandis que la page affiche le titre de la section. Le résultat actuel ne change pas tant que vous n’en cliquez pas un.

Chaque document mémorise le côté où vous avez placé la recherche. Pour la remettre dans la barre latérale, choisissez de nouveau Show Search on Right pour désactiver l’option. Pour la masquer lorsqu’elle est à droite, cliquez sur le bouton de fermeture (×) à côté. Pour l’afficher de nouveau, appuyez sur ⌘F ou cliquez sur le bouton Search en haut de la barre latérale.

La recherche partage le côté droit avec l’[Inspector](rulers-and-inspector.md#the-inspector). Lorsque les deux sont ouverts, passez de l’un à l’autre avec les boutons Search et Inspector en haut.

## Relancer une recherche déjà faite

Chaque document mémorise les 10 dernières recherches pour lesquelles vous êtes allé à un résultat. Pour en relancer une :

- Cliquez sur la loupe du champ de recherche et choisissez-la, ou
- Le champ de recherche étant vide, cliquez dessus dans la liste Recent Searches, sous le champ.

VectorPDF va au résultat le plus proche. Pour oublier les recherches d'un document, choisissez Clear Recent Searches dans la loupe, ou cliquez sur Clear au-dessus de la liste. Appliquer des caviardages à un document efface aussi ses recherches récentes.

## Options de recherche {#search-options}

Cliquez sur le bouton d’options à côté du champ de recherche :

- **Match Case :** trouve uniquement le texte qui a la même casse.
- **Whole Word :** ignore les correspondances à l’intérieur de mots plus longs.
- **Smart Search :** cette option est activée sauf si vous la désactivez. Les espaces, les traits d’union, les tirets et les sauts de ligne sont considérés comme équivalents : « end-to-end » trouve donc aussi « end to end », même sur deux lignes. Les guillemets droits et courbes sont également équivalents.
- **Show Search on Right :** déplace la recherche de la barre latérale vers la droite de la fenêtre, pour que vous puissiez la voir [à côté du plan](#see-results-beside-the-outline).

## Ignorer les éléments parasites du texte {#ignore-clutter-in-the-text}

Certains documents placent des marqueurs au milieu des phrases, comme des numéros de citation, ce qui empêche de trouver une expression. Smart Search peut les ignorer.

1. Choisissez VectorPDF > Settings, puis cliquez sur Advanced.
2. À côté d’Ignored Search Patterns, cliquez sur Edit.
3. Ajoutez l’un des motifs prédéfinis ou votre propre expression régulière, puis activez-le.

Les motifs prédéfinis couvrent les citations numériques comme [12], les symboles de marque, la pagination par astérisque comme *123 et les balises de commentaire IEEE 802.11.

## Documents numérisés

Les pages numérisées ne contiennent aucun texte consultable tant qu’elles n’ont pas été reconnues. Consultez [Rechercher et sélectionner du texte dans des pages numérisées](scanned-pages.md).

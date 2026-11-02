<!-- keywords: rechercher, recherche, trouver, résultat suivant, casse, mot entier, recherche intelligente, motifs ignorés, expression régulière, balises, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, PDF -->
<!-- source: 9b70f3b5ae8c -->

# Rechercher dans un document

## Trouver du texte

1. Appuyez sur ⌘F. VectorPDF affiche l’onglet Search dans la barre latérale.
2. Saisissez ce que vous cherchez. Les résultats apparaissent au fur et à mesure, à partir de la page où vous êtes.

Chaque résultat indique sa page et le texte qui l’entoure, et chaque occurrence est surlignée dans le document.

## Passer d’un résultat à l’autre

| Pour | Procédez ainsi |
| --- | --- |
| Passer au résultat suivant | Appuyez sur Return ou ⌘G, ou cliquez sur la flèche vers le bas |
| Passer au résultat précédent | Appuyez sur ⇧Return ou ⇧⌘G, ou cliquez sur la flèche vers le haut |
| Accéder à n’importe quel résultat | Cliquez dessus |
| Parcourir la liste | Cliquez sur un résultat, puis appuyez sur les touches fléchées |

Cliquez avec le bouton droit sur un résultat pour [créer une ancre](anchors.md) à partir de celui-ci ou l’ouvrir dans une nouvelle fenêtre.

## Options de recherche {#search-options}

Cliquez sur le bouton d’options à côté du champ de recherche :

- **Match Case :** trouve uniquement le texte qui a la même casse.
- **Whole Word :** ignore les correspondances à l’intérieur de mots plus longs.
- **Smart Search :** cette option est activée sauf si vous la désactivez. Les espaces, les traits d’union, les tirets et les sauts de ligne sont considérés comme équivalents : « end-to-end » trouve donc aussi « end to end », même sur deux lignes. Les guillemets droits et courbes sont également équivalents.

## Ignorer les éléments parasites du texte {#ignore-clutter-in-the-text}

Certains documents placent des marqueurs au milieu des phrases, comme des numéros de citation, ce qui empêche de trouver une expression. Smart Search peut les ignorer.

1. Choisissez VectorPDF > Settings.
2. À côté d’Ignored Search Patterns, cliquez sur Edit.
3. Ajoutez l’un des motifs prédéfinis ou votre propre expression régulière, puis activez-le.

Les motifs prédéfinis couvrent les citations numériques comme [12], les symboles de marque, la pagination par astérisque comme *123 et les balises de commentaire IEEE 802.11.

## Documents numérisés

Les pages numérisées ne contiennent aucun texte consultable tant qu’elles n’ont pas été reconnues. Consultez [Rechercher dans des pages numérisées avec l’OCR](scanned-pages.md).

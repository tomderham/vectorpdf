<!-- keywords: fenêtre, barre d’outils, barres d’outils, barre latérale, onglets, écran de démarrage, indicateur de page, commandes, pièces jointes, window, toolbar, toolbars, sidebar, tabs, start screen, interface, page indicator, controls, attachments, barre d’état, Inspector, status bar -->
<!-- source: 52234d6db490 -->

# La fenêtre de VectorPDF

Chaque fenêtre de VectorPDF comporte une barre d’outils, une barre latérale et le document lui-même. Une fenêtre peut contenir plusieurs documents sous forme d’[onglets](tabs-and-windows.md).

## Barre d’outils

| Commande | Fonction |
| --- | --- |
| Titre du document | Affiche le nom du document. Cliquez dessus avec le bouton droit pour accéder à Favorites et Tab Groups. |
| Zoom | Les boutons − et + modifient le zoom par paliers. Cliquez sur le pourcentage pour saisir votre propre valeur. |
| Rotate Left et Rotate Right | Font pivoter la présentation. Le PDF enregistré n’est pas modifié. |
| Two-Page Mode | Affiche les pages côte à côte, comme un livre ouvert. |
| Horizontal Scrolling | Dispose les pages de gauche à droite, autant que la fenêtre peut en contenir. |
| Markup Toolbar | Affiche les [outils d’annotation](text-markup.md). |
| Measurement Toolbar | Affiche les [outils de mesure](measure.md). |
| Page | Les flèches permettent d’avancer d’une page à la fois. Cliquez sur le numéro de page pour saisir la page souhaitée. |

Consultez [Zoom, rotation et disposition des pages](zoom-and-layout.md) pour en savoir plus sur ces commandes.

## Barre latérale

Les onglets en haut de la barre latérale permettent de basculer entre :

- **Outline & Thumbnails :** la [table des matières ou une vignette de chaque page](outline-and-thumbnails.md).
- **Search :** les [résultats pour le document actif](search.md). Vous pouvez déplacer Search sur le côté droit de la fenêtre pour la voir [à côté du plan](search.md#see-results-beside-the-outline).
- **Anchors :** [les endroits que vous avez enregistrés](anchors.md).
- **Document :** ce que le document contient en plus de ses pages : ses [calques](layers.md), ses [pièces jointes](attachments.md), ses [signatures numériques](digital-signatures.md) et, si vous les activez dans les réglages, ses [champs de formulaire, liens et destinations](document-tab.md). Choisissez ce qui s’affiche dans le menu en haut de l’onglet. Cet onglet n’apparaît que si le document en contient au moins un.
- **Comments :** [toutes les annotations, avec leurs réponses et leur statut](draw-and-notes.md#see-all-annotations).
- **Ask About This Document :** [l’Agent](agent.md). Cet onglet apparaît sous macOS 26 ou version ultérieure, sauf si vous avez désactivé [Use Agent](settings.md) dans Settings.

Utilisez le bouton de la barre latérale dans la barre d’outils pour afficher ou masquer la barre latérale. VectorPDF mémorise, pour chaque document, si vous l’avez affichée ou masquée. La première fois que vous ouvrez un document, la barre latérale s’affiche, sauf si le document n’a qu’une ou deux pages et rien pour la barre latérale : ni table des matières, ni calques, annotations ou pièces jointes. Un document court contenant des pièces jointes ou des calques s’ouvre sur l’onglet Document qui les affiche, et un document contenant des annotations sur l’onglet Comments.

## Barres d’outils supplémentaires

Trois barres d’outils apparaissent sous la barre d’outils principale lorsque vous en avez besoin. Choisissez-les dans le menu View :

- **Markup** (⇧⌘A) contient les [outils d’annotation](text-markup.md).
- **Measurement** (⇧⌘M) contient les [outils de mesure](measure.md).
- **Redact** (⌥⌘R) contient les [outils de caviardage](redact.md).

Le menu View peut aussi afficher une barre d’état sous la page, des règles, une grille, l’Inspector à côté de la page et un navigateur dans le coin. Voir [Règles, barre d’état et Inspector](rulers-and-inspector.md).

## Menus du clic droit

De nombreuses commandes figurent aussi dans les menus qui s’affichent lorsque vous cliquez avec le bouton droit, ou en maintenant la touche Contrôle enfoncée, sur le document, la barre latérale ou la barre d’outils. Consultez [Menus du clic droit](right-click-menus.md).

## Indicateur de page

Lorsque vous changez de page, un petit indicateur de page apparaît brièvement sur le document, avec des flèches pour passer à la page précédente ou suivante. Lorsque la barre d’outils Measurement est affichée, il indique aussi l’échelle de plan de la page.

## Écran Start

Une fenêtre ou un onglet vide affiche l’écran Start, avec la zone de dépôt, puis vos Tab Groups, Favorites et Recent Documents. Cliquez sur une ligne pour l’ouvrir. Maintenez le pointeur sur une ligne et cliquez sur le bouton •••, ou cliquez sur la ligne avec le bouton droit, pour l’ouvrir dans un nouvel onglet ou une nouvelle fenêtre, l’afficher dans le Finder ou la retirer.

L’écran Start liste jusqu’à trois Tab Groups et cinq Favorites. Le menu Favorites les liste tous.

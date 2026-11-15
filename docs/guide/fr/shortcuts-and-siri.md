<!-- keywords: Raccourcis, Siri, Spotlight, automatisation, action, actions, demander, rechercher, extraire des pages, ouvrir un document, flux de travail, Shortcuts, automation, App Intents, ask, search, extract pages, open document, workflow -->
<!-- source: 0598b760c342 -->

# Utiliser VectorPDF avec Raccourcis et Siri

VectorPDF ajoute des actions à l’app Raccourcis : vous pouvez les utiliser dans vos propres raccourcis, ainsi que depuis Spotlight et Siri.

| Action | Fonction |
| --- | --- |
| Ask About Document | Pose une question à l’[Agent](agent.md) et renvoie sa réponse, avec les numéros de page cités |
| Search Document | Recherche du texte, comme le champ de recherche, et renvoie chaque occurrence avec son numéro de page |
| Extract Pages | Crée un PDF à partir de certaines pages d’un PDF, comme `1-3, 5` |
| Open Document | Ouvre un document dans VectorPDF, à une page donnée si vous en indiquez une |

Si vous ne choisissez pas de document pour Ask, Search ou Extract Pages, l’action utilise le document au premier plan dans VectorPDF.

## Utiliser une action dans un raccourci

1. Ouvrez l’app Raccourcis, puis créez un raccourci ou ouvrez-en un.
2. Recherchez VectorPDF dans la liste des actions, puis faites glisser une action dans votre raccourci.
3. Renseignez l’action. Pour utiliser un fichier provenant d’une étape précédente du raccourci, par exemple d’une action qui obtient un fichier, cliquez sur Document et choisissez-le.

Chaque action transmet ce qu’elle renvoie : la réponse, la liste des occurrences ou le nouveau PDF. Vous pouvez ensuite l’envoyer à une autre action, par exemple une action qui crée un PDF, ajoute à une note ou envoie un message.

Si les actions de VectorPDF n’apparaissent pas, ouvrez VectorPDF une fois, puis quittez et rouvrez Raccourcis.

## Demander à Siri

Vous pouvez dire ou taper ces phrases à Siri. Siri demande tout ce qui lui manque, comme votre question. Les phrases sont en anglais, car VectorPDF n’est pas encore traduit : elles fonctionnent lorsque Siri est réglé en anglais :

- "Ask VectorPDF about this document"
- "Search this document in VectorPDF"
- "Extract pages in VectorPDF"
- "Open a document in VectorPDF"

Vous pouvez aussi trouver les actions en tapant leur nom dans Spotlight.

## À propos de chaque action

- **Ask About Document** ouvre le document dans VectorPDF s’il n’est pas ouvert, derrière la fenêtre dans laquelle vous travaillez. La question et la réponse apparaissent aussi dans l’onglet Ask About This Document du document : vous pouvez y lire les sources et poser d’autres questions. L’Agent doit être activé, et la réponse provient du moteur choisi dans [Choisir comment l’Agent répond](agent-engines.md). Si aucune réponse ne peut être générée, l’action renvoie les passages les plus pertinents.
- **Search Document** utilise Smart Search et vos [Ignored Search Patterns](search.md#ignore-clutter-in-the-text), avec Match Case et Whole Words si vous les activez. L’action renvoie jusqu’à 100 occurrences et indique leur nombre total. Un document ouvert est recherché tel qu’il est dans VectorPDF, avec ses modifications non enregistrées et uniquement les calques affichés ; les autres documents sont recherchés sans être ouverts.
- **Extract Pages** accepte des pages et des plages séparées par des virgules. Une plage comme `5-` va jusqu’à la dernière page, et `3-1` donne les pages dans l’ordre inverse. L’action lit le fichier tel qu’il a été enregistré pour la dernière fois et ne le modifie pas. Le nouveau PDF est nommé d’après le document et les pages, par exemple « Report (Pages 1-3, 5).pdf ».
- **Open Document** met l’onglet du document au premier plan s’il est déjà ouvert.

Un document protégé par mot de passe doit être ouvert dans VectorPDF, avec son mot de passe saisi, pour que Search Document puisse y rechercher. Extract Pages ne peut pas utiliser de documents protégés par mot de passe.

> **Remarque :** Ce qu’une action renvoie est transmis à Raccourcis ou à Siri, puis à l’étape suivante de votre raccourci. Ask About Document n’envoie que ce que l’Agent enverrait si vous posiez la question dans VectorPDF. Consultez [Confidentialité](privacy.md).

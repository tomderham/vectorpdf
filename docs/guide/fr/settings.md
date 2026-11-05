<!-- keywords: réglages, préférences, mises à jour, mise à jour, rechercher des mises à jour, navigateur, auteur, auteur des annotations, stockage, espace disque, effacer, supprimer les données, désinstaller, settings, preferences, options, updates, update, check for updates, browser, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->
<!-- source: 95e6c661738e -->

# Réglages

Choisissez VectorPDF > Settings, ou appuyez sur ⌘,.

| Réglage | Fonction |
| --- | --- |
| Annotation Author | Le nom enregistré sur vos annotations et réponses. S’il est vide, VectorPDF utilise votre nom d’utilisateur Mac. |
| Use Agent | Affiche l’onglet [Ask About This Document](agent.md) dans la barre latérale, sous macOS 26 ou version ultérieure. |
| AI Synthesis Engine | Choisit [ce qui rédige les réponses de l’Agent](agent-engines.md), sous macOS 27. |
| PDF Color | Définit [l’aspect des pages](pdf-colors.md) : Follow System, Light, Dark ou Sepia. |
| Open Links In | Choisit le navigateur pour les liens web. |
| Ignored Search Patterns | Liste le texte que [Smart Search ignore](search.md#ignore-clutter-in-the-text). |
| Digital Stamp | Crée, modifie ou supprime votre [tampon](stamps.md). |
| Sync reading positions with iCloud | Conserve votre [page, zoom, ancres](reading-positions.md) et vos [recherches récentes](search.md) sur vos autres Mac. |
| Storage | Indique l’espace qu’occupent les données de VectorPDF et permet de [les effacer](#free-up-space-or-remove-data). |
| Automatically check for updates | Recherche une nouvelle version sur GitHub environ une fois par jour. Cliquez sur Check Now pour lancer une recherche à tout moment. |

## Libérer de l’espace ou supprimer les données {#free-up-space-or-remove-data}

Sous Storage, les réglages indiquent l’espace occupé par chaque type de données :

- **Index de l’Agent :** ce que l’Agent crée pour répondre aux questions sur un document. Cliquez sur Clear pour les supprimer ; un document est de nouveau indexé la prochaine fois que vous utilisez l’Agent avec lui. VectorPDF les maintient sous 500 Mo en supprimant d’abord les moins récemment utilisés, et supprime l’index d’un document lorsque celui-ci n’existe plus.
- **Historique de lecture :** la dernière page, le zoom, les ancres et les recherches récentes de chaque document. Cliquez sur Clear pour les oublier, sur ce Mac et dans iCloud.
- **Fichiers temporaires :** copies créées lors de la modification, de l’enregistrement, de l’impression ou de l’exportation, et mises à jour téléchargées. VectorPDF supprime celles qui restent à sa prochaine ouverture.

Pour supprimer tout ce que VectorPDF a stocké, cliquez sur Remove All VectorPDF Data. Vos réglages, favoris, groupes d’onglets, tampon et clés API sont aussi supprimés, puis VectorPDF se ferme. Vos documents ne sont pas modifiés. Enregistrez ou fermez d’abord les documents dont les modifications ne sont pas enregistrées.

## Mettre à jour VectorPDF

Choisissez VectorPDF > Check for Updates. Si une nouvelle version est disponible, cliquez sur Download. Une fois le téléchargement terminé, cliquez sur **Quit and Open Installer**, puis faites glisser VectorPDF dans votre dossier Applications.

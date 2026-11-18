<!-- keywords: modifier le plan, ajouter un signet, plan à partir des titres, titres, créer une table des matières, renommer, mettre en retrait, plan, table des matières, sommaire, signets, vignette, vignettes, barre latérale, outline, table of contents, TOC, contents, bookmarks, thumbnail, thumbnails, sidebar, bookmark, add bookmark, edit outline, build outline, headings, generate table of contents, rename, indent, outdent -->
<!-- source: 4dd1a582a981 -->

# Plan et vignettes

Cliquez sur l’onglet Outline & Thumbnails en haut de la barre latérale, puis choisissez **Outline** ou **Thumbnails**.

## Plan

Le plan est la table des matières du document, s’il en a une. La section que vous lisez est mise en évidence pendant le défilement.

- **Accéder à une section :** cliquez dessus. Son titre défile près du haut de la fenêtre, ou reste où il est si vous le voyez déjà.
- **Afficher ou masquer les sous-sections :** cliquez sur la flèche à côté d’une section.
- **Trouver une section :** saisissez du texte dans le champ « Search outline ». Seules les sections correspondantes sont affichées.
- **Garder une section à portée de main :** cliquez dessus avec le bouton droit pour créer une [ancre](anchors.md) ou l’ouvrir dans une nouvelle fenêtre.

## Modifier le plan {#edit-the-outline}

Vous pouvez ajouter des entrées au plan d’un document (d’autres apps les appellent parfois signets), et les renommer, les déplacer et les supprimer. Les modifications font partie du fichier lorsque vous l’[enregistrez](save.md).

Pour ajouter une entrée, allez à l’endroit vers lequel elle doit mener, puis choisissez Edit > Add Outline Entry (⌥⌘B). Si vous avez sélectionné du texte, l’entrée mène à ce texte, qui est proposé comme titre. Sinon, elle mène au haut de la page que vous lisez. Saisissez un titre, puis cliquez sur **Add**. Les entrées ajoutées ainsi se placent parmi les entrées de premier niveau dans l’ordre des pages : c’est donc aussi ainsi que l’on commence un plan pour un document qui n’en a pas.

Pour le reste, cliquez avec le bouton droit sur une entrée :

| Pour | Choisissez |
| --- | --- |
| Ajouter une entrée après celle-ci, ou à l’intérieur | Add Entry After ou Add Entry Inside |
| La renommer | Rename |
| La faire mener au texte sélectionné, ou à la page que vous lisez | Go Here Instead |
| La déplacer parmi les entrées de son niveau | Move Up ou Move Down |
| La placer dans l’entrée au-dessus, ou la sortir de celle où elle se trouve | Indent ou Outdent |
| La supprimer, avec les entrées qu’elle contient | Delete Entry |

Vous pouvez aussi faire glisser une entrée pour la déplacer, ou la déposer sur une autre entrée pour la placer à l’intérieur. Les entrées qu’elle contient se déplacent avec elle. Tant que le plan est filtré par le champ « Search outline », les entrées ne peuvent pas être modifiées. Edit > Undo (⌘Z) annule les modifications du plan, une à une.

### Créer un plan à partir des titres

Choisissez Edit > Build Outline from Headings pour créer en une seule étape un plan à partir des titres du document. La commande se trouve aussi dans le menu contextuel d’une entrée du plan. Si le document a déjà un plan, une confirmation vous est demandée avant qu’il soit remplacé ; Edit > Undo le rétablit.

Dans un PDF balisé, les titres sont ceux que marquent ses balises. Dans les autres PDF, VectorPDF recherche les lignes qui se distinguent du corps du texte : plus grandes, ou en gras là où le texte ne l’est pas. Un style plus grand correspond à un niveau plus élevé qu’un style plus petit, et les numéros de section comme 3.2.1 donnent les niveaux au sein d’un même style. Les en-têtes et pieds de page courants, les légendes de figures et de tableaux et les lignes d’une table des matières sont ignorés.

Vérifiez le résultat : les styles d’un document n’indiquent pas toujours quelles lignes sont des titres. Renommez, déplacez ou supprimez les entrées comme indiqué ci-dessus. Les titres des pages numérisées ne sont pas trouvés, même une fois leur texte reconnu.

## Vignettes

Les vignettes montrent toutes les pages. Cliquez sur une vignette pour accéder à cette page.

Maintenez la touche ⌘ enfoncée pour sélectionner plusieurs pages, ou la touche ⇧ pour sélectionner une plage. Faites-les ensuite glisser vers un nouvel emplacement, ou cliquez avec le bouton droit pour les faire pivoter, les dupliquer, les extraire ou les supprimer. Consultez [Réorganiser les pages](pages.md).

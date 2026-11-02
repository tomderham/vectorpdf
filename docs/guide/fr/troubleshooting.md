<!-- keywords: damaged, corrupt, unreadable, dépannage, problème, problèmes, ne fonctionne pas, aide, résoudre, assistance, troubleshooting, problem, problems, not working, help, fix, support -->
<!-- source: e9a1c8cbf4d9 -->

# Dépannage

## Je ne peux pas sélectionner du texte, suivre des liens ni utiliser les outils d’annotation

Vérifiez que la présentation n’est pas pivotée ni en Two-Page Mode. Ces fonctions ne sont disponibles qu’en présentation Single Page, sans rotation. Consultez [Zoom, rotation et disposition des pages](zoom-and-layout.md).

Vérifiez aussi qu’aucun outil Markup ou Measurement n’est actif. Appuyez sur Escape pour revenir à la sélection de texte.

## Une recherche ne trouve rien

- Les pages sont peut-être numérisées. Consultez [Rechercher dans des pages numérisées avec l’OCR](scanned-pages.md).
- Vérifiez que Match Case et Whole Word sont désactivés dans les [options de recherche](search.md#search-options), et que Smart Search est activé.
- Si des marqueurs interrompent le texte, ajoutez un [motif ignoré](search.md#ignore-clutter-in-the-text).

## Maintenir la touche ⌘ n’affiche pas d’aperçu

Link Peek fonctionne sur les liens du document et sur les liens web vers des documents ouverts dans un autre onglet. Les références en texte brut ne sont pas des liens : cliquez dessus avec le bouton droit. Consultez [Références entre documents](cross-document-references.md).

La fenêtre de VectorPDF doit aussi être la fenêtre active.

## Une référence à un autre document est introuvable

Ouvrez l’autre document dans un onglet de la même fenêtre. La recherche ne porte pas sur les fenêtres séparées.

## Un document est signalé comme endommagé

Si VectorPDF ne trouve aucune page dans un fichier, il indique que le fichier n’a pas pu être ouvert. Le fichier est peut-être endommagé ou incomplet, ou il utilise des fonctionnalités que VectorPDF ne peut pas lire. Essayez de le télécharger à nouveau ou de l’ouvrir dans une autre app PDF.

## Un document en ligne ne s’ouvre pas

Vérifiez votre connexion et que le fichier se télécharge dans le Finder, puis réessayez.

## L’Agent n’est pas disponible ou n’affiche que des passages

L’Agent nécessite macOS 26 ou une version ultérieure, et la rédaction de réponses sur l’appareil nécessite qu’Apple Intelligence soit activé et prêt. Si l’indexation échoue, cliquez sur Retry dans l’onglet Ask About This Document. Consultez [Choisir comment l’Agent répond](agent-engines.md).

## Un modèle en ligne ne répond pas

Vérifiez la clé API et le modèle dans [Settings](settings.md), et que votre compte auprès du service dispose de crédit. VectorPDF répond sur l’appareil si le service échoue.

## Mes modifications ont disparu

Les modifications doivent être [enregistrées](save.md). Si une autre app a modifié le fichier alors que vous aviez des modifications non enregistrées, choisir Reload from Disk les supprime.

## L’aide n’affiche pas ce guide

Tips ne peut afficher ce guide que si VectorPDF se trouve dans votre dossier Applications. Déplacez-le dans ce dossier, puis choisissez à nouveau Help > VectorPDF Help.

## Obtenir de l’aide supplémentaire

Signalez un problème ou posez une question sur [GitHub](https://github.com/tomderham/vectorpdf/issues). Un exemple de PDF est utile, si vous pouvez en partager un.

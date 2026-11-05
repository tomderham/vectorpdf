<!-- keywords: enregistrer, enregistrer sous, non enregistré, partager, afficher dans le Finder, modifications, revenir, dernière version enregistrée, recharger, annuler les modifications, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all -->
<!-- source: 2c2bdeb1617c -->

# Enregistrer vos modifications

Les annotations, les données de formulaire, les modifications de pages et les caviardages ne sont écrits dans votre fichier que lorsque vous enregistrez. Une fenêtre contenant des modifications non enregistrées affiche un point dans son bouton de fermeture.

| Pour | Procédez ainsi |
| --- | --- |
| Enregistrer | Choisissez File > Save, ou appuyez sur ⌘S |
| Enregistrer une copie sous un nouveau nom | Choisissez File > Save As, ou appuyez sur ⇧⌘S |
| Enregistrer une copie protégée par mot de passe | Choisissez File > [Save Encrypted with Password](passwords.md), ou appuyez sur ⌥⌘S |

Si vous fermez un document contenant des modifications non enregistrées, VectorPDF vous demande s’il faut les enregistrer.

## Annuler vos modifications

Pour abandonner tout ce que vous avez fait depuis le dernier enregistrement, choisissez File > Revert to Saved. VectorPDF vous le demande d’abord, puis ouvre le fichier tel qu’il a été enregistré pour la dernière fois, à la page que vous lisiez. Cette opération est irréversible.

Pour créer une copie plus légère d’un document, consultez [Optimized PDF](export.md#optimized-pdf).

## Partager un document

Choisissez File > Share pour utiliser un service de partage de macOS, ou File > Show in Finder (⇧⌘R) pour trouver le fichier. Dans l’écran Start, cliquez avec le bouton droit sur un document pour l’afficher dans le Finder.

## Ce qui n’est pas enregistré dans le PDF

Certains éléments restent dans VectorPDF et ne voyagent pas avec le fichier : les [ancres](anchors.md), votre [position de lecture](reading-positions.md), la rotation de la présentation et le texte issu de l’[OCR](scanned-pages.md).

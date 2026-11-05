<!-- keywords: pièces jointes, pièce jointe, fichiers joints, fichiers incorporés, trombone, portfolio, facture électronique, enregistrer la pièce jointe, extraire, attachments, attachment, attached files, embedded files, paperclip, portfolio, e-invoice, electronic invoice, ZUGFeRD, Factur-X, XML, Quick Look, save attachment, extract -->
<!-- source: 72d1207c7468 -->

# Fichiers joints à un PDF

Un PDF peut contenir d’autres fichiers : une feuille de calcul accompagnant un rapport, une maquette CAO accompagnant un jeu de plans, ou les données d’une facture électronique. Lorsqu’un document contient des pièces jointes, l’onglet Attachments (un trombone) apparaît en haut de la barre latérale. Un document d’une seule page contenant des pièces jointes s’ouvre avec la barre latérale affichée.

Chaque pièce jointe affiche son nom et, lorsque le PDF les fournit, sa description, sa taille et la page à laquelle elle est jointe. Maintenez le pointeur sur l’une d’elles pour voir son type de fichier et sa date.

| Pour | Procédez ainsi |
| --- | --- |
| Prévisualiser une pièce jointe | Double-cliquez dessus, ou sélectionnez-la et appuyez sur la barre d’espace |
| Prévisualiser la suivante ou la précédente | Quick Look ouvert, appuyez sur la touche Flèche vers le bas ou Flèche vers le haut |
| L’ouvrir dans son app | Cliquez dessus avec le bouton droit et choisissez Open |
| Enregistrer une copie | Cliquez dessus avec le bouton droit et choisissez Save As…, ou faites-la glisser vers le Finder |
| Les enregistrer toutes | Cliquez sur Save All… en haut de l’onglet, puis choisissez un dossier |
| Aller à sa page | Cliquez dessus avec le bouton droit et choisissez Show on Page |

> **Attention :** Une pièce jointe peut être n’importe quel type de fichier, y compris une app ou un script. N’ouvrez que des fichiers de confiance. VectorPDF marque comme téléchargés les fichiers qu’il extrait d’un PDF, afin que macOS vérifie les apps et les scripts avant leur exécution, comme pour les fichiers venant du web.

## Factures électroniques

Les factures ZUGFeRD et Factur-X contiennent leurs données dans un fichier XML, généralement nommé `factur-x.xml` ou `zugferd-invoice.xml`. Il figure parmi les autres pièces jointes, pour que vous puissiez l’enregistrer pour votre logiciel de comptabilité. VectorPDF n’affiche pas lui-même le détail de la facture.

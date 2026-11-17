<!-- keywords: métré, tableau, tableau de métré, quantités, totaux, mesures, takeoff, take-off, table, schedule, CSV, quantities, totals, measurements, comptage, comptages, count, counts -->
<!-- source: 4b652eba713c -->

# Tableau de métré

Le tableau de métré récapitule toutes les mesures d’un document, avec leur page, leur type, leur valeur et leur échelle, ainsi que les totaux de longueur et de surface. Les [comptages](measure.md#count-things-on-a-drawing) occupent une ligne par groupe sur chaque page, comme « Outlets × 12 », et sont totalisés par groupe pour tout le document.

Cliquez sur **Takeoff Table** dans la [barre d’outils Measurement](measure.md).

- **Copy Table** copie le tableau, prêt à être collé dans une feuille de calcul.
- **Export CSV** l’enregistre dans un fichier.

Dans un document avec des [calques](layers.md), le tableau indique aussi le calque de chaque mesure et omet les mesures des calques masqués, pour que vous puissiez totaliser un corps de métier à la fois.

Les totaux additionnent les longueurs (cotes et périmètres) et les surfaces de toutes les pages. Chaque mesure utilise l’échelle de sa page, et les totaux sont affichés dans les unités de la première mesure.

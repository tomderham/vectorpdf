<!-- keywords: intestazione, intestazioni, piè di pagina, numeri di pagina, numerazione delle pagine, Bates, numeri Bates, numerazione Bates, filigrana, filigrane, BOZZA, RISERVATO, legale, header, headers, footer, footers, page numbers, page numbering, Bates numbers, Bates numbering, watermark, watermarks, DRAFT, CONFIDENTIAL, stamp text, legal, discovery, PDF -->
<!-- source: 7e05ab7492d9 -->

# Intestazioni, piè di pagina, numeri Bates e filigrane

Puoi inserire del testo in alto e in basso nelle pagine, come un titolo, i numeri di pagina o i numeri Bates, e una filigrana come BOZZA o RISERVATO in diagonale. Scegli Edit > Headers, Footers and Watermark, compila le parti che vuoi, quindi fai clic su **Add**.

VectorPDF conserva nel documento le tue scelte, così in seguito puoi modificare o rimuovere intestazioni, piè di pagina e filigrana. Scegli di nuovo Edit > Headers, Footers and Watermark, apporta le modifiche, quindi fai clic su **Update**. Per rimuoverli tutti, fai clic su **Remove All**.

Le modifiche entrano a far parte del file quando lo [salvi](save.md).

## Intestazione e piè di pagina

Scrivi in una qualsiasi delle sei caselle: a sinistra, al centro e a destra dell’intestazione e del piè di pagina. Lascia vuota una casella per non inserirvi nulla.

Per aggiungere un numero di pagina o un altro valore che cambia da una pagina all’altra, fai clic in una casella, quindi scegli dal menu **Insert**:

| Insert | Mostra |
| --- | --- |
| Page Number | Il numero della pagina, contando dalla prima pagina marcata. Consulta [Pagine e numeri](#pages-and-numbers). |
| Page Count | Quante pagine ha il documento |
| Bates Number | Il numero Bates della pagina |
| Date | La data di oggi |
| File Name | Il nome del file del documento |

Ognuno compare nella casella come una parola tra doppie parentesi angolari, ad esempio `<<page>>`. Per esempio, digita `Pagina `, inserisci Page Number, digita ` di `, quindi inserisci Page Count per ottenere “Pagina 3 di 12”.

Puoi scegliere font, dimensione e colore del testo, e i margini: la distanza dell’intestazione dal bordo superiore della pagina, del piè di pagina da quello inferiore, e di entrambi dai lati, in punti (72 punti fanno un pollice).

## Filigrana

Digita il testo della filigrana. Premi A capo per una seconda riga. Poi scegli:

- **Font** e **Color**.
- **As large as fits the page**, oppure una dimensione a tua scelta.
- **Opacity:** quanto è visibile. Una filigrana leggera lascia la pagina leggibile.
- **Angle:** orizzontale, diagonale o verticale.
- **Behind the page's content:** disegna la filigrana sotto il testo e le immagini della pagina anziché sopra. Una pagina con uno sfondo, come una pagina scansionata, nasconde una filigrana che si trova dietro.

## Pagine e numeri {#pages-and-numbers}

- **Pages:** tutte le pagine, le pagine dispari o pari, e da una pagina a un’altra. Lascia vuoto From o To per la prima o l’ultima pagina.
- **First page marked is page:** il numero che Page Number assegna alla prima pagina marcata. I numeri aumentano di uno per ogni pagina marcata.
- **Bates numbers:** un prefisso, come il nome di una causa o di un’azienda, il numero di cifre, il numero da cui partire e un suffisso. I numeri Bates aumentano di uno per ogni pagina marcata e sono completati con zeri, ad esempio ACME-000001. Inserisci Bates Number in un’intestazione o in un piè di pagina per mostrarli.

## Da sapere

- Intestazioni, piè di pagina e filigrane fanno parte della pagina, non sono [annotazioni](draw-and-notes.md), quindi vengono stampati e compaiono in altre app. Sono contrassegnati come decorazione della pagina, che i lettori di schermo possono saltare. Puoi cercare e selezionare il loro testo.
- I margini si misurano sulla pagina come viene mostrata, quindi su una pagina ruotata l’intestazione resta in alto.
- VectorPDF può modificare o rimuovere solo le intestazioni, i piè di pagina e le filigrane che ha aggiunto. Quelli aggiunti da altre app fanno parte del contenuto della pagina.
- Aggiungerli a un documento [firmato digitalmente](digital-signatures.md) modifica ciò che è stato firmato, quindi le sue firme non sono più valide.

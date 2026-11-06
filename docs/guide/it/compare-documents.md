<!-- keywords: confrontare, confronto, differenze, revisione, versioni, modifiche, affiancati, scorrimento sincronizzato, rinumerazione, numeri di pagina, riferimenti incrociati, sommario, compare, comparison, diff, difference, differences, revision, revisions, redline, changes, versions, side by side, synchronized scrolling, scroll together, renumbering, page numbers, cross-references, table of contents -->
<!-- source: 84d22a753af8 -->

# Confrontare due documenti

Compare Documents mostra due versioni di un documento affiancate, evidenziando in entrambe il testo che è cambiato. Quando scorri una versione, l’altra scorre fino allo stesso testo, anche dove tra le versioni sono state aggiunte o rimosse pagine.

## Aprire un confronto

1. Scegli File > Compare Documents.
2. Scegli il documento originale (Original) e quello rivisto (Revised). Ogni menu elenca i documenti aperti; scegli Choose File per sceglierne un altro. Il documento in primo piano è inizialmente l’originale. Fai clic su Swap per scambiarli.
3. Fai clic su Compare.

Puoi anche fare clic con il pulsante destro sul titolo del documento, o su una parte vuota della barra degli strumenti, e scegliere un documento in Compare With. In questo modo il documento in primo piano viene confrontato con quello che scegli.

Il confronto si apre in una nuova scheda, con l’originale a sinistra e la revisione a destra. Lì entrambi sono di sola lettura. Per modificarne uno, aprilo in una scheda a sé.

## Leggere le modifiche

- Le parole rimosse dall’originale sono evidenziate in rosso, a sinistra.
- Le parole aggiunte nella revisione sono evidenziate in verde, a destra.
- Dove il testo è stato aggiunto solo da una parte, una sottile barra dall’altra parte indica dove si troverebbe.
- Il testo uguale in entrambi ma in un altro punto è sottolineato in blu da entrambe le parti, per esempio una tabella che cade dall’altra parte di un’interruzione di pagina, o una clausola spostata. Servono almeno dieci parole di seguito. Il testo spostato non conta come modifica; in cima alla scheda Changes è indicato quanti passaggi si trovano in un altro punto.

La scheda Changes nella barra laterale elenca ogni modifica: le parole rimosse barrate in rosso, quelle aggiunte in verde e il numero di pagina nella revisione. Fai clic su una modifica per andarci in entrambi i documenti.

Per scorrere le modifiche una alla volta, fai clic sulla freccia su o giù in cima alla scheda Changes, scegli Go > Previous Change o Go > Next Change, oppure premi ⌥⌘Up Arrow o ⌥⌘Down Arrow. La scheda indica a quale modifica sei, per esempio 3 of 12. Quella modifica è evidenziata più intensamente e selezionata nell’elenco.

Viene confrontato solo il testo. Le modifiche a formattazione, immagini o disegni non vengono mostrate. Intestazioni, piè di pagina e numeri di pagina vengono esclusi, così non appaiono come modifiche quando le pagine si spostano.

## Trovare una sezione o una parola

Le schede Outline & Thumbnails e Search della barra laterale agiscono sulla revisione, come in qualsiasi scheda. Vai a una sezione o a un risultato di ricerca e l’originale segue fino allo stesso testo.

## Scorrere e ingrandire insieme

La riga a circa un terzo dall’alto di ciascun lato mostra lo stesso testo. Quando un lato ha del testo che l’altro non ha, l’altro aspetta finché non l’hai superato. Puoi scorrere entrambi i lati; l’altro segue.

Ingrandire un lato ingrandisce entrambi, e il testo che stai leggendo resta dov’è. Ingrandendo oltre la larghezza della pagina, scorrere un lato in orizzontale scorre anche l’altro, così entrambi mostrano la stessa parte della pagina.

## Opzioni di confronto

In cima alla scheda Changes, scegli Ignore Case o Ignore Punctuation per escludere le differenze di maiuscole o di punteggiatura. Le virgolette tipografiche e diritte, e i diversi tipi di trattino, contano sempre come uguali.

### Ignorare la rinumerazione

Quando si aggiunge o si rimuove una clausola, una figura o una tabella, tutto ciò che segue viene rinumerato e ogni numero di pagina successivo cambia. In un documento lungo, la maggior parte delle modifiche può consistere in nuovi numeri nel sommario, nell’elenco delle figure e nei riferimenti incrociati. Ignore Renumbering, attivo fin dall’inizio, li esclude:

- Una voce del sommario o di un elenco delle figure, o un riferimento incrociato come “vedi 9.4.2.18”, non conta come modificata quando rimanda allo stesso punto in entrambe le versioni, anche se il suo numero o il suo numero di pagina è nuovo.
- Nel punto a cui rimanda, anche il numero del titolo o della didascalia non conta come modificato, se è cambiato allo stesso modo. Per esempio, “Figure 9-806” che diventa “Figure 9-809”.

Che cosa conta come lo stesso punto dipende dai link dei documenti, non dall’aspetto dei numeri. Un riferimento incrociato che ora rimanda altrove viene comunque mostrato come modifica, così come un numero che non fa parte di un link, per esempio “Table 9-12” scritto come testo semplice. Un titolo riformulato viene comunque mostrato come modificato nel titolo stesso, anche dove la sua voce nel sommario non lo è.

Ignore Renumbering richiede documenti con link interni, che la maggior parte delle app di videoscrittura e di impaginazione crea per il sommario e i riferimenti incrociati. Non è disponibile quando nessuno dei due documenti ne contiene. Un PDF salvato di nuovo da un’app che elimina i link non ne ha, anche se l’originale li aveva.

Per vedere ogni numero cambiato, disattiva Ignore Renumbering.

## Se il confronto non è utile

- **Un documento non ha testo da confrontare:** le pagine scansionate non hanno testo finché non viene riconosciuto. Vedi [Cercare e selezionare il testo nelle pagine scansionate](scanned-pages.md).
- **Questi documenti hanno poco testo in comune:** forse non sono versioni dello stesso documento.

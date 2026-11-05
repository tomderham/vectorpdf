<!-- keywords: livelli, livello, contenuto facoltativo, CAD, disegni tecnici, mostrare, nascondere, visibilità, annotazioni, nuovo livello, rinominare livello, eliminare livello, layers, layer, optional content, OCG, AutoCAD, Revit, show, hide, visibility, markups, annotations, new layer, rename layer, delete layer -->
<!-- source: 0a0a671f9044 -->

# Mostrare e nascondere i livelli

I disegni esportati dai programmi CAD e di progettazione spesso mettono ogni parte di una tavola su un livello proprio: muri, impianto elettrico, idraulico, quote, nuvole di revisione. Puoi mostrarli o nasconderli uno per uno.

Il pannello Layers compare in cima alla barra laterale solo quando il documento ha livelli. Per dare a un documento il suo primo livello, consulta [Aggiungere, rinominare ed eliminare i livelli](#add-rename-and-delete-layers).

- **Mostrare o nascondere un livello:** fai clic sulla sua casella. La pagina viene ridisegnata subito.
- **Scegliere uno di un gruppo:** alcuni documenti raggruppano i livelli in modo che se ne veda uno solo alla volta, come le lingue o le scale di una tavola. Questi hanno pulsanti rotondi; sceglierne uno nasconde gli altri.
- **Intestazioni:** raggruppano i livelli elencati sotto di esse e non possono essere nascoste.
- **Livelli bloccati:** hanno un lucchetto accanto. Il documento non permette di mostrarli o nasconderli.

I livelli che nascondi vengono esclusi anche quando [stampi](print.md), [selezioni il testo](select-text.md) o [cerchi](search.md), così lavori solo con ciò che vedi.

## Mettere le annotazioni su un livello

Anche le annotazioni possono stare su un livello, così vengono mostrate e nascoste con esso. Le altre app che leggono i livelli, come Acrobat e Bluebeam, le mostrano e nascondono allo stesso modo.

- **Scegliere dove vanno le nuove annotazioni:** nella [barra degli strumenti Markup](draw-and-notes.md) o nella [barra degli strumenti Measurement](measure.md), fai clic sul menu dei livelli (indica **No Layer** finché non ne scegli uno) e scegli un livello. Tutto ciò che crei da quel momento va su quel livello, finché non scegli un altro livello o **No Layer**. Puoi anche fare clic con il pulsante destro su un livello nel pannello Layers e scegliere **Put New Annotations Here**. Il livello delle nuove annotazioni ha una matita accanto.
- **Spostare un'annotazione su un altro livello:** fai clic con il pulsante destro su di essa e scegli **Layer**, quindi un livello, oppure **None** per toglierla da qualsiasi livello.
- **Aggiungere un livello tuo:** consulta [Aggiungere, rinominare ed eliminare i livelli](#add-rename-and-delete-layers).

Il menu dei livelli compare solo quando un documento ha livelli, quindi le barre degli strumenti degli altri documenti non cambiano.

Le annotazioni su un livello nascosto spariscono dalla pagina, dal [pannello Comments](draw-and-notes.md#see-all-annotations) e dalla [tabella dei computi](takeoff.md), e non possono essere selezionate né cancellate. La tabella Annotations continua a elencarle, con il loro livello.

Se scegli un livello nascosto per le nuove annotazioni, viene mostrato, così ciò che crei non sparisce. Undo rimette un'annotazione sul livello in cui si trovava.

## Aggiungere, rinominare ed eliminare i livelli {#add-rename-and-delete-layers}

I revisori spesso mettono le proprie annotazioni su livelli propri, ad esempio uno per categoria di lavori o per giro di revisione, anche su disegni arrivati senza livelli. Ognuno di questi comandi modifica il documento e Undo lo annulla.

- **Aggiungere un livello:** scegli Edit > New Layer…, poi dagli un nome. Funziona in qualsiasi PDF, quindi è così che un documento ottiene il suo primo livello; compaiono poi il pannello Layers e i menu dei livelli. Le nuove annotazioni vanno sul nuovo livello. In un documento che ha già livelli, puoi anche fare clic su **+** in cima al pannello Layers o scegliere **New Layer…** dal menu dei livelli.
- **Rinominare un livello:** scegli Edit > Rename Layer…, scegli il livello, poi digita il nuovo nome.
- **Eliminare un livello:** scegli Edit > Delete Layer…, poi il livello. Le sue annotazioni restano sulla pagina, senza livello. Si possono eliminare solo i livelli che contengono soltanto annotazioni: eliminare un livello su cui si trova il disegno stesso lascerebbe quella parte del disegno sempre visibile, quindi quei livelli non sono elencati.

## Cosa viene salvato

I livelli che aggiungi, rinomini o elimini vengono salvati con il documento, così come i livelli su cui si trovano le annotazioni.

Quali livelli sono mostrati non viene salvato con il documento. La prossima volta che lo apri, i suoi livelli vengono mostrati come stabilisce il documento stesso, e chiunque lo riceva da te vede lo stesso.

> **Nota:** Un documento di una o due pagine con livelli si apre sul pannello Layers, a meno che tu non abbia nascosto la barra laterale per quel documento. Usa il pulsante della barra laterale nella barra degli strumenti per mostrarla.

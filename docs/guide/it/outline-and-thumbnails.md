<!-- keywords: modificare la struttura, aggiungere segnalibro, struttura dai titoli, titoli, creare sommario, rinominare, rientro, struttura, indice, sommario, contenuti, segnalibri, miniatura, miniature, barra laterale, outline, table of contents, TOC, contents, bookmarks, thumbnail, thumbnails, sidebar, bookmark, add bookmark, edit outline, build outline, headings, generate table of contents, rename, indent, outdent -->
<!-- source: 4dd1a582a981 -->

# Struttura e miniature

Fai clic sul pannello Outline & Thumbnails nella parte superiore della barra laterale, quindi scegli **Outline** o **Thumbnails**.

## Struttura

La struttura è l'indice del documento, se presente. La sezione che stai leggendo viene evidenziata mentre scorri.

- **Andare a una sezione:** fai clic su di essa. Il suo titolo scorre vicino alla parte superiore della finestra, oppure resta dov'è se lo vedi già.
- **Mostrare o nascondere le sottosezioni:** fai clic sulla freccia accanto a una sezione.
- **Trovare una sezione:** digita nel campo “Search outline”. Vengono mostrate solo le sezioni corrispondenti.
- **Tenere a portata di mano una sezione:** fai clic su di essa con il tasto destro per creare un [ancoraggio](anchors.md) o per aprirla in una nuova finestra.

## Modificare la struttura {#edit-the-outline}

Puoi aggiungere voci alla struttura di un documento (altre app possono chiamarle segnalibri), e rinominarle, spostarle ed eliminarle. Le modifiche entrano a far parte del file quando lo [salvi](save.md).

Per aggiungere una voce, vai al punto a cui deve portare, quindi scegli Edit > Add Outline Entry (⌥⌘B). Se hai selezionato del testo, la voce porta a quel testo, che viene proposto come titolo. Altrimenti porta all’inizio della pagina che stai leggendo. Digita un titolo, quindi fai clic su **Add**. Le voci aggiunte in questo modo si inseriscono tra le voci di primo livello in ordine di pagina, quindi è anche il modo per iniziare una struttura in un documento che non ne ha.

Per tutto il resto, fai clic con il tasto destro su una voce:

| Per | Scegli |
| --- | --- |
| Aggiungere una voce dopo questa o al suo interno | Add Entry After o Add Entry Inside |
| Rinominarla | Rename |
| Farla portare al testo selezionato o alla pagina che stai leggendo | Go Here Instead |
| Spostarla tra le voci del suo livello | Move Up o Move Down |
| Metterla dentro la voce sopra, o toglierla da quella in cui si trova | Indent o Outdent |
| Eliminarla, con le voci che contiene | Delete Entry |

Puoi anche trascinare una voce per spostarla, o rilasciarla su un’altra voce per metterla al suo interno. Le voci che contiene si spostano con lei. Mentre la struttura è filtrata dal campo “Search outline”, le voci non possono essere modificate. Edit > Undo (⌘Z) annulla le modifiche alla struttura, una alla volta.

### Creare una struttura dai titoli

Scegli Edit > Build Outline from Headings per creare in un solo passaggio una struttura con i titoli del documento. Il comando si trova anche nel menu contestuale di una voce della struttura. Se il documento ha già una struttura, ti viene chiesta conferma prima di sostituirla; Edit > Undo la ripristina.

In un PDF con tag, i titoli sono quelli indicati dai suoi tag. Negli altri PDF, VectorPDF cerca le righe che si distinguono dal testo: più grandi, o in grassetto dove il testo non lo è. Uno stile più grande è un livello più alto di uno più piccolo, e i numeri di sezione come 3.2.1 danno i livelli all’interno di uno stesso stile. Intestazioni e piè di pagina ripetuti, didascalie di figure e tabelle e le righe di un sommario vengono esclusi.

Controlla il risultato: gli stili di un documento non dicono sempre quali righe sono titoli. Rinomina, sposta o elimina le voci come descritto sopra. I titoli delle pagine scansionate non vengono trovati, neanche dopo che il loro testo è stato riconosciuto.

## Miniature

Le miniature mostrano tutte le pagine. Fai clic su una miniatura per passare a quella pagina.

Tieni premuto ⌘ per selezionare più pagine, oppure ⇧ per selezionare un intervallo. Quindi trascinale in una nuova posizione, oppure fai clic con il tasto destro per ruotarle, duplicarle, estrarle o eliminarle. Consulta [Riordinare le pagine](pages.md).

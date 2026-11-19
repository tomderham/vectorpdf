<!-- keywords: rettangolo, cerchio, raggio, diametro, arco, lunghezza dell’arco, misurare, misura, misurazione, misurazioni, lunghezza, distanza, quota, perimetro, area, angolo, orto, aggancio, measure, measurement, measurements, length, distance, dimension, perimeter, angle, ortho, snap, snapping, modificare, spostare, maniglia, scostamento, edit, change, move, reshape, handle, offset, contare, conteggio, simboli, count, counting, tally, symbols, rectangle, circle, radius, diameter, arc, arc length, curve -->
<!-- source: fea799877718 -->

# Misurare lunghezze, aree e angoli, e contare

Premi ⇧⌘M per mostrare la barra degli strumenti Measurement. Se il disegno è in scala, [imposta prima la scala](drawing-scale.md).

Per misurare con precisione, ingrandisci prima la vista. Premendo Escape annulli una misurazione in corso. Premi di nuovo Escape, o fai clic sullo strumento selezionato, per posare lo strumento.

## Strumenti di misurazione

| Strumento | Come usarlo |
| --- | --- |
| Linear Dimension | Trascina da un punto all'altro. |
| Perimeter | Fai clic su ogni punto lungo il percorso. Per terminare, premi Return o fai doppio clic. |
| Polygon Area | Fai clic su ogni angolo. Per chiudere la forma, premi Return, fai doppio clic o fai clic sul primo punto. |
| Rectangle Area | Trascina da un angolo a quello opposto. |
| Circle | Trascina dal centro al bordo. L’etichetta mostra l’area e il diametro, e la [barra di stato](rulers-and-inspector.md) mostra anche raggio e circonferenza. |
| Arc Length | Fai clic dove inizia l’arco, su un punto lungo l’arco e dove finisce. L’etichetta mostra la lunghezza lungo l’arco e il suo raggio. |
| Vertex Angle | Fai clic su un punto della prima linea, quindi sul vertice e infine su un punto della seconda linea. |
| Count | Digita ciò che stai contando nella casella del gruppo, ad esempio Prese, poi fai clic su ciascuno. |

## Contare elementi su un disegno {#count-things-on-a-drawing}

Scegli lo strumento Count, poi digita il nome di un gruppo nella casella accanto, ad esempio Prese o Porte tipo A, oppure scegli dal menu accanto alla casella un gruppo già presente nel documento. Ogni clic colloca un indicatore, un punto del colore della barra Measurement, e la barra mostra quanti elementi di quel gruppo ci sono nella pagina. Cambia il nome del gruppo per contare qualcos'altro; ogni gruppo viene contato a parte. Usa un colore diverso per ogni gruppo per distinguerli sulla pagina.

Per spostare un indicatore, trascinalo con lo strumento Select. Per toglierne uno, fai clic su di esso con il tasto destro e scegli Delete Count Marker. La [tabella Takeoff](takeoff.md) mostra quanti ce ne sono per ogni gruppo in ogni pagina, con i totali. Gli indicatori vengono salvati nel PDF come piccoli cerchi, quindi anche le altre app li mostrano.

## Disegnare con precisione

- **Ortho Lock** mantiene le linee a 0°, 45° e 90°. Tieni premuto ⇧ per invertirlo per una sola linea: per misurare con qualsiasi angolo quando è attivo, o per mantenere dritta una linea quando è disattivo.
- **Vertex Magnetic Snapping** aggancia il puntatore agli angoli e alle estremità nel disegno.
- **Guide e griglia:** con View > Rulers and Grid > Snap to Guides and Grid attivo, i punti si agganciano alle guide trascinate dai righelli e alla griglia mentre è visibile. Consulta [Righelli, barra di stato e Inspector](rulers-and-inspector.md).
- **La barra di stato** (View > Show Status Bar) mostra di una misurazione, mentre la disegni, più di quanto mostri la sua etichetta: il suo angolo e quanto si estende in orizzontale e in verticale, oppure il perimetro di un’area fino a quel momento.

## Modificare una misurazione

Scegli **Select**, la freccia all'inizio della barra Measurement, oppure premi Escape per posare lo strumento di misurazione. Punta su una misurazione e un contorno tratteggiato la mostra; fai clic su di essa per selezionarla. Fai clic tenendo premuto ⇧ per selezionarne diverse, oppure tieni premuto ⌥ e trascina sopra di esse. Con uno strumento di misurazione in uso, un clic misura di nuovo.

Una misurazione selezionata ha delle maniglie sui suoi punti.

| Per | Esegui questa operazione |
| --- | --- |
| Spostare un punto | Trascina la sua maniglia. Ortho Lock e l'aggancio funzionano come quando misuri. |
| Spostare l'intera misurazione | Trascina la sua linea o premi i tasti freccia (con ⇧ si sposta di 10 punti). |
| Avvicinare o allontanare una linea di quota da ciò che misura | Trascina la sua etichetta oppure, una volta staccata dai punti, la linea di quota stessa. |
| Cambiarne il colore | Scegli un colore con il pulsante del colore nella barra degli strumenti Measurement. |
| Cambiarne lo spessore della linea | Scegli o digita uno spessore nella casella dello spessore della barra Measurement. |

Il valore viene ricalcolato mentre trascini. Trascina oltre il bordo della finestra per scorrere, se la misurazione è più lunga della vista. Scegli Edit > Undo per riportare una misurazione com'era. Puoi modificare anche le misurazioni già salvate nel PDF.

Per selezionare un'area, fai clic sul suo bordo: un clic al suo interno seleziona il testo che si trova lì.

Un rettangolo, un cerchio o un arco mantiene la sua forma quando lo modifichi: trascina un angolo del rettangolo, il centro o il bordo del cerchio, o uno dei tre punti dell’arco. Vengono salvati come un’area o una lunghezza lungo il loro contorno, così anche le altre app che leggono le misurazioni PDF li mostrano come misurazioni, con valori propri per il contorno (entro lo 0,05% di quelli di VectorPDF per un cerchio o un arco).

## Modificare l'aspetto delle misurazioni

Usa il pulsante del colore e la casella dello spessore nella barra degli strumenti Measurement prima di misurare. Scegli uno spessore in punti oppure digitane uno, da 0,1 a 72 punti. Le nuove misurazioni sono grigie, spesse 1,5 punti, finché non scegli altro. VectorPDF ricorda la tua scelta, e la barra Markup mantiene i propri colori e spessori. Per cambiare il colore o lo spessore di una misurazione già creata, selezionala, quindi scegli un colore o uno spessore nella barra Measurement. Lo spessore viene salvato nel PDF.

## Conservare o rimuovere le misurazioni

Le misurazioni sono annotazioni, memorizzate nel PDF quando [salvi](save.md). Per eliminarne una, fai clic con il tasto destro su di essa, quindi scegli il comando di eliminazione, come Delete Dimension, Delete Area Takeoff, Delete Circle Measurement o Delete Count Marker.

Per elencare tutte le misurazioni, consulta la [tabella Takeoff](takeoff.md).

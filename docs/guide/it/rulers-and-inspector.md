<!-- keywords: barra di stato, posizione del puntatore, coordinate, dimensioni della pagina, formato carta, righelli, guide, griglia, aggancio, unità, millimetri, pollici, punti, Inspector, font, dimensione del font, colore, risoluzione delle immagini, navigatore, conteggio parole, conteggio caratteri, status bar, pointer position, coordinates, page size, paper size, A4, Letter, ARCH, rulers, guides, grid, snap, units, millimeters, inches, points, font size, color, image resolution, dpi, ppi, line width, navigator, pan and zoom, word count, character count -->
<!-- source: a8ac6b2f855f -->

# Righelli, barra di stato e Inspector

Mostrano dove si trovano le cose in una pagina e di cosa sono fatte. Restano disattivati finché non li attivi nel menu View, così la lettura resta pulita.

## La barra di stato

Scegli View > Show Status Bar (⌘/) per mostrare una striscia sotto la pagina. Mostra:

- **Dove si trova il puntatore** sulla pagina, dall’angolo in alto a sinistra della pagina. In una pagina con una [scala del disegno](drawing-scale.md), mostra quel punto anche in unità reali.
- **Le dimensioni della pagina** sotto il puntatore, o della pagina corrente, con il formato carta quando corrisponde a uno: da A0 ad A6, da B3 a B5, Letter, Legal, Tabloid, da ANSI C a E e da ARCH A a E. Le serie di disegni spesso mescolano formati di tavola, quindi il valore cambia passando da una pagina all’altra.
- **Una misurazione mentre la disegni:** la lunghezza, l’angolo e quanto si estende in orizzontale (ΔX) e in verticale (ΔY); la lunghezza di un perimetro fino a quel momento e il suo ultimo segmento; un’area fino a quel momento e il suo perimetro. Consulta [Misurare lunghezze, aree e angoli](measure.md).
- **Le dimensioni della selezione di testo,** in parole e caratteri.

Scegli le unità, Millimeters, Inches o Points, dal menu a destra della barra di stato. Le usano anche i righelli, la griglia e l’Inspector.

## Righelli e guide

Scegli View > Rulers and Grid > Show Rulers (⌘R) per mostrare i righelli lungo il lato superiore e sinistro della pagina. Misurano la pagina sotto il puntatore dal suo angolo in alto a sinistra, e una linea su ogni righello mostra dove si trova il puntatore.

| Per | Fai così |
| --- | --- |
| Aggiungere una guida | Trascina da un righello sulla pagina |
| Spostare una guida | Trascinala |
| Rimuovere una guida | Trascinala fuori dalla pagina |
| Rimuovere tutte le guide | Scegli View > Rulers and Grid > Clear Guides |

Le guide appartengono alla pagina su cui le metti. Restano finché il documento è aperto e non vengono salvate al suo interno.

## La griglia

Scegli View > Rulers and Grid > Show Grid (⌘') per disegnare una griglia su ogni pagina, dal suo angolo in alto a sinistra. Scegli la spaziatura da View > Rulers and Grid > Grid Spacing. Una linea ogni cinque è più scura.

Quando **Snap to Guides and Grid** è attivo in View > Rulers and Grid, i punti di una misurazione si agganciano alle guide vicine al puntatore, e alla griglia mentre è visibile, come si agganciano agli angoli con Vertex Magnetic Snapping.

## L’Inspector {#the-inspector}

Scegli View > Show Inspector (⌃⌘I) per mostrare l’Inspector accanto alla pagina. Puoi anche fare clic con il tasto destro sulla pagina e scegliere Inspect.

- **Testo, immagini e disegni:** con l’Inspector aperto, fai clic sulla pagina in modalità Select. L’Inspector mostra cosa è disegnato lì, e la pagina lo evidenzia:
  - **Testo:** il font, la sua dimensione, il carattere, il suo colore e spazio colore, e se il font è incluso nel file. Un font che non lo è viene sostituito da un altro, che in stampa può avere un aspetto diverso.
  - **Immagini:** la dimensione in pixel, la risoluzione così come sono collocate sulla pagina, la dimensione sulla pagina, lo spazio colore e i bit per componente. Controlla la risoluzione di un’immagine prima di stampare o ottimizzare.
  - **Disegni:** lo spessore e il colore di una linea, o il colore di riempimento di una forma.
- **Annotazioni:** seleziona un’annotazione per vederne tipo, autore, date, livello, opacità e colore. Per spostarla, scrivi la sua posizione (**X** e **Y**, dall’angolo in alto a sinistra della pagina) e premi A capo. Rettangoli, ovali, caselle di testo, callout, timbri e nuvole di revisione si possono anche ridimensionare: scrivi **Width** e **Height**.

## Il navigatore

Scegli View > Show Navigator (⌃⌘N) per mostrare, nell’angolo della finestra, una miniatura della pagina visibile. La parte sullo schermo è riquadrata. Trascina il riquadro, o fai clic sulla miniatura, per spostarti su una tavola grande con uno zoom elevato.

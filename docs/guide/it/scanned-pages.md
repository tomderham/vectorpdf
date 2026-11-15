<!-- keywords: OCR, scansione, scansionato, scansioni, riconoscimento del testo, riconoscere il testo, immagine, selezionare, copiare, evidenziare, scan, scanned, scans, text recognition, recognize text, image, Run OCR, select, copy, highlight, PDF ricercabile, salvare il testo, livello di testo, lingua, searchable PDF, save text, text layer, language -->
<!-- source: 8b77a345a44e -->

# Cercare e selezionare il testo nelle pagine scansionate

Una pagina scansionata è un'immagine di testo. VectorPDF può riconoscere il testo sul Mac tramite il riconoscimento ottico dei caratteri (OCR), così puoi eseguire ricerche al suo interno, selezionarlo e annotarlo.

## Come funziona

Quando apri un documento, VectorPDF cerca le pagine scansionate tra le prime 50 pagine e ne riconosce il testo in background. Quando c'è altro da elaborare, il pannello Search mostra quante pagine scansionate ha trovato.

- **Per riconoscere tutte le pagine scansionate trovate,** fai clic su **Run OCR** nel pannello Search.
- Anche una ricerca le riconosce, quindi puoi semplicemente iniziare a cercare.

Le evidenziazioni seguono il testo, anche se la pagina è stata scansionata leggermente inclinata.

Il testo viene riconosciuto nelle lingue delle impostazioni Lingua e Zona del Mac supportate dal riconoscimento, oppure in inglese se nessuna è supportata.

## Selezionare il testo riconosciuto

Dopo che una pagina è stata riconosciuta, puoi [selezionarne e copiarne](select-text.md) il testo ed [evidenziarlo, sottolinearlo o barrarlo](text-markup.md) come in qualsiasi altra pagina. Il riconoscimento può richiedere un momento, e le pagine dopo le prime 50 richiedono prima Run OCR o una ricerca.

Il riconoscimento può commettere errori, quindi controlla tutto ciò che copi e che deve essere esatto. Le selezioni iniziano e finiscono in modo netto ai bordi delle parole. All'interno di una parola, le loro estremità sono approssimative.

> **Nota:** il testo riconosciuto viene usato finché il documento è aperto e non viene salvato nel PDF, a meno che tu non scelga di salvarlo (vedi sotto). Le annotazioni che aggiungi vengono salvate. Se oscuri o ruoti una pagina, il suo testo viene riconosciuto di nuovo.

## Salvare il testo riconosciuto nel PDF {#save-the-recognized-text-in-the-pdf}

Per rendere un PDF scansionato ricercabile anche in altre app, come Anteprima, Spotlight e Acrobat, salva al suo interno il testo riconosciuto. Il testo viene aggiunto come livello invisibile sotto ogni pagina scansionata, nel punto in cui è stato riconosciuto, quindi le pagine restano uguali.

- **Per salvarlo nel documento,** scegli File > Save with Recognized Text, oppure fai clic su **Save in PDF** nel pannello Search quando il testo è stato riconosciuto. Vengono salvate anche le altre modifiche.
- **Per salvarlo in una copia,** scegli File > Export Document As > Searchable PDF. Il documento aperto non cambia.

In entrambi i casi, VectorPDF riconosce prima le pagine scansionate non ancora elaborate, mostrando l'avanzamento. Ogni pagina richiede un momento. Puoi fare clic su Cancel e non viene salvato nulla.

Ricevono testo solo le pagine che non ne hanno di proprio. Una volta che il testo è nel file, quelle pagine non vengono più trattate come scansionate: VectorPDF seleziona e cerca il testo salvato, come fanno le altre app.

> **Importante:** il riconoscimento può commettere errori, e il testo salvato va ovunque vada il file: negli indici di ricerca, nel testo copiato e nei lettori di schermo. Verifica che il testo sia corretto prima di farvi affidamento, oppure salva una copia. Salvare nel documento lo riapre anche dal file, quindi non puoi annullare le modifiche fatte prima del salvataggio.

<!-- keywords: esportare, esportazione, convertire, testo semplice, testo, appiattire, appiattito, riepilogo annotazioni, ottimizzare, ottimizzato, ridurre dimensioni, comprimere, più leggero, immagini, font, contorni, testo in contorni, plotter, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF, optimize, optimized, reduce file size, compress, smaller, downsample, images, fonts, subset, outlines, text to outlines, plotter -->
<!-- source: 0e99b5515751 -->

# Esportare in altri formati

Per esportare un intero documento, scegli File > Export Document As, quindi scegli Plain Text, Word Document, Scalable Vector Graphics, Flattened PDF o Optimized PDF. Il riepilogo delle annotazioni e le misurazioni hanno comandi propri.

## Plain Text

Salva il testo del documento in un file `.txt`.

## Word Document

Salva un file `.docx` che puoi modificare in Word e in altre app. I layout di pagina complessi possono apparire diversi rispetto al PDF.

## SVG

Salva ogni pagina come file Scalable Vector Graphics, con il testo convertito in tracciati vettoriali, in modo che appaia esattamente come nel PDF. Un documento di più pagine viene salvato come cartella con un file per pagina.

## Flattened PDF {#flattened-pdf}

Salva un PDF in cui le annotazioni e i campi dei moduli diventano parte della pagina, quindi non possono più essere modificati. Nella finestra di salvataggio, scegli cosa appiattire:

- **Flatten annotations and markups**
- **Flatten form fields (make static)**

> **Nota:** l'appiattimento non rimuove ciò che si trova sotto. Per rimuovere contenuti, usa l'[oscuramento](redact.md).

## Optimized PDF {#optimized-pdf}

Salva una copia più leggera del PDF, comprese le modifiche che non hai ancora salvato. Il documento aperto non cambia. I dati che il documento non usa più vengono rimossi, i duplicati uniti e tutto viene compresso. Nella finestra di dialogo di salvataggio puoi anche scegliere:

- **Keep only the characters each font uses:** rimuove le parti dei font incorporati che il documento non usa. Attivo per impostazione predefinita.
- **Images:** lascia le immagini come sono oppure riducile a 300 dpi (per la stampa) o 150 dpi (per la lettura a schermo). Vengono ridotte solo le immagini con risoluzione maggiore. Le foto vengono salvate in JPEG; diagrammi e istantanee dello schermo restano senza perdita. Le scansioni in bianco e nero non vengono modificate.
- **Convert text to outlines:** disegna ogni lettera come una forma, così il documento appare uguale su plotter, plotter da taglio e sistemi di stampa che non dispongono dei suoi font. Il testo della copia non può essere selezionato, cercato né copiato.

Quanto si riduce la copia dipende dal documento. Scansioni e foto si riducono di più quando ne riduci le immagini.

## Riepilogo delle annotazioni

Scegli File > Export Annotations Summary (⇧⌘E) per salvare un elenco delle annotazioni del documento, comprese quelle di altre app, con autori, stati e risposte. Per impostazione predefinita viene creato un file Markdown. Assegna al file l'estensione `.csv` per salvare invece un foglio di calcolo.

## Misurazioni

Per esportare le misurazioni, usa la [tabella Takeoff](takeoff.md).

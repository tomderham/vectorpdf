<!-- keywords: oscurare, oscuramento, oscuramenti, rimuovere, cancellare, sensibile, carta di credito, email, telefono, data, trova e oscura, metadati, segnalibri, allegati, redact, redaction, redactions, remove, black out, sensitive, SSN, credit card, phone, date, find and redact, metadata, bookmarks, attachments, PDF -->
<!-- source: d8be777cd6d7 -->

# Oscurare contenuti sensibili

L'oscuramento rimuove definitivamente i contenuti da un PDF. VectorPDF elimina dal file il testo, i pixel delle immagini e la grafica vettoriale sotto l'area oscurata, insieme a tutte le annotazioni e ai campi dei moduli che la toccano. Non si limita a coprirli con un riquadro e, quando salvi, le revisioni precedenti non vengono conservate.

La prima volta che oscuri qualcosa in un documento, un avviso spiega cos'altro cambia:

- **Rimossi dall'intero documento:** i metadati come titolo e autore, gli allegati, le miniature delle pagine, il testo alternativo per l'accessibilità e i dati dei moduli XFA. Per conservarli, oscura una copia.
- **I segnalibri restano,** e ogni parola oscurata nei loro titoli viene sostituita da [Redacted]. Il testo nelle immagini e nelle scansioni non può essere confrontato, quindi controlla tu i segnalibri dopo averli oscurati.
- **Non rimossi:** destinazioni con nome, etichette di pagina, nomi dei livelli e JavaScript. Potrebbero contenere ancora il testo.

> **Attenzione:** l'oscuramento ha effetto non appena lo applichi e non è disponibile il comando Undo. Il file originale non cambia finché non salvi, quindi per ricominciare chiudi il documento senza salvare. Conserva una copia dell'originale e usa Save As per salvare la versione oscurata con un nuovo nome.

Premi ⌥⌘R oppure scegli View > Show Redact Toolbar.

## Oscurare un'area

1. Scegli **Redact Region**.
2. Scegli Black o White come colore di oscuramento.
3. Trascina sull'area da oscurare.

## Trovare e oscurare

1. Scegli **Find & Redact**.
2. Scegli cosa cercare:
   - **Text / Phrase**, con le opzioni Match Case e Whole Word.
   - **Custom Regular Expression**, ad esempio `[A-Z]{3}-\d{5}`.
   - **Social Security Number (SSN)**, **Credit Card Number**, **Email Address**, **Phone Number** o **Date**. Queste opzioni trovano automaticamente i formati più comuni.
3. Fai clic su Find.
4. Controlla le corrispondenze. Fai clic su una corrispondenza per vederla nella sua pagina e deseleziona quelle che vuoi conservare.
5. Scegli un'azione:
   - **Redact** rimuove il contenuto e lascia un riquadro nero o bianco.
   - **Remove** rimuove il contenuto senza lasciare alcun riquadro.
6. Fai clic su **Redact Selected** o **Remove Selected**.

> **Attenzione:** il rilevamento automatico può non trovare tutto, soprattutto i formati insoliti o il testo nelle immagini. Controlla il documento prima di condividerlo. Il testo nelle pagine scansionate deve essere oscurato con Redact Region.

## Salvare il risultato

Premi ⇧⌘S per salvare il documento oscurato con un nuovo nome. Il salvataggio elimina anche l'indice di ricerca dell'[Agent](agent.md) del documento, che potrebbe contenere il testo rimosso.

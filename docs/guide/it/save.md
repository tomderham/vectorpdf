<!-- keywords: salvare, salva con nome, non salvato, condividere, modifiche, ripristina, ultima versione salvata, ricaricare, annullare le modifiche, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all, salvataggio automatico, recuperare, recupero, arresto anomalo, chiusura inaspettata, autosave, recover, recovery, crash, quit unexpectedly -->
<!-- source: cdbdeb12d33f -->

# Salvare le modifiche

Le annotazioni, i dati inseriti nei moduli, le modifiche alle pagine e gli oscuramenti non vengono scritti nel file finché non salvi. Una finestra con modifiche non salvate mostra un punto nel pulsante di chiusura.

| Per | Esegui questa operazione |
| --- | --- |
| Salvare | Scegli File > Save oppure premi ⌘S |
| Salvare una copia con un nuovo nome | Scegli File > Save As oppure premi ⇧⌘S |
| Salvare una copia protetta da password | Scegli File > [Save Encrypted with Password](passwords.md) oppure premi ⌥⌘S |

Se chiudi un documento con modifiche non salvate, VectorPDF chiede se vuoi salvarle.

Un documento [firmato digitalmente](digital-signatures.md) viene salvato aggiungendo le tue modifiche dopo la parte firmata, così le sue firme restano valide nella misura in cui le modifiche sono consentite.

## Annullare le modifiche

Per eliminare tutto ciò che hai fatto dall'ultimo salvataggio, scegli File > Revert to Saved. VectorPDF chiede prima conferma, poi apre il file com'era all'ultimo salvataggio, alla pagina che stavi leggendo. L'operazione non può essere annullata.

Per creare una copia più leggera di un documento, consulta [Optimized PDF](export.md#optimized-pdf).

## Se VectorPDF si chiude inaspettatamente {#if-vectorpdf-quits-unexpectedly}

Finché un documento ha modifiche non salvate, VectorPDF ne conserva una copia sul Mac, aggiornata circa ogni 30 secondi. Se VectorPDF si chiude inaspettatamente, alla successiva apertura propone le copie:

- **Open Recovered Copy** salva ogni copia accanto al suo originale, con il nome "(Recovered)", e la apre. L'originale non cambia. Confrontali, poi tieni quello che preferisci.
- **Decide Later** conserva le copie e chiede di nuovo la volta successiva.
- **Discard Changes** elimina le copie.

La copia viene eliminata quando salvi il documento, lo ripristini o lo chiudi senza salvare, e quando esci da VectorPDF. I documenti protetti da password non vengono copiati, perché la copia non sarebbe crittografata.

## Condividere un documento

Scegli File > Share per usare un servizio di condivisione di macOS, oppure File > Show in Finder (⇧⌘R) per trovare il file. Nella schermata Start, fai clic con il tasto destro su un documento per mostrarlo nel Finder.

## Cosa non viene salvato nel PDF

Alcuni elementi restano in VectorPDF e non viaggiano con il file: gli [ancoraggi](anchors.md), la [posizione di lettura](reading-positions.md), la rotazione della vista e il testo ottenuto con l'[OCR](scanned-pages.md), a meno che tu non lo [salvi nel PDF](scanned-pages.md#save-the-recognized-text-in-the-pdf).

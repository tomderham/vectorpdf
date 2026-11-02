<!-- keywords: privacy, riservatezza, dati, rete, telemetria, analisi, iCloud, sicurezza, data, network, telemetry, analytics, security -->
<!-- source: 4fdc452a0a96 -->

# Privacy

VectorPDF non prevede account, analisi, telemetria né segnalazione degli arresti anomali. I documenti vengono elaborati sul Mac e nessun loro contenuto viene inviato allo sviluppatore.

## Cosa usa la rete

- **Controllo degli aggiornamenti:** VectorPDF chiede a GitHub l'ultima versione circa una volta al giorno, oppure quando scegli Check for Updates. La richiesta non contiene informazioni su di te o sui tuoi documenti. Puoi disattivare questa funzione in [Settings](settings.md).
- **L'Agent:** con il motore On-Device nulla esce dal Mac. [Private Cloud Compute e i modelli online](agent-engines.md) inviano la tua domanda e alcuni passaggi del documento, e solo quando fai una domanda. La configurazione di un modello online usa inoltre la tua chiave per elencare i modelli disponibili e inviare un breve test.
- **iCloud:** lo stato di lettura viene conservato nel tuo account iCloud: la posizione del file, l'ultima pagina e lo zoom, e i nomi, gli estratti e le pagine degli ancoraggi. I documenti, il loro testo completo e le miniature degli ancoraggi non vengono caricati.
- **I link su cui fai clic** si aprono nel browser.
- **Servizi Apple:** Translation, Look Up, la sintesi vocale e l'OCR sono forniti da macOS e possono scaricare file di lingua da Apple. Handoff condivide con gli altri dispositivi il documento e la pagina che stai leggendo.

## Cosa viene conservato sul Mac

VectorPDF conserva le preferenze, i preferiti, i gruppi di pannelli, le posizioni di lettura, gli ancoraggi e il timbro. Conserva anche un indice dei documenti che hai usato con l'Agent, le miniature degli ancoraggi e le copie di lavoro temporanee dei documenti con modifiche alle pagine od oscuramenti non salvati, che elimina quando non servono più.

Le chiavi API dei modelli online vengono conservate nel portachiavi login.

Per tutti i dettagli, consulta l'[informativa sulla privacy su GitHub](https://github.com/tomderham/vectorpdf/blob/main/PRIVACY.md).

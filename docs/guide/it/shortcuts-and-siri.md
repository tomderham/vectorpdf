<!-- keywords: Comandi Rapidi, Siri, Spotlight, automazione, azione, azioni, chiedere, cercare, estrarre pagine, aprire documento, flusso di lavoro, Shortcuts, automation, action, actions, App Intents, ask, search, extract pages, open document, workflow -->
<!-- source: 0598b760c342 -->

# Usare VectorPDF con Comandi Rapidi e Siri

VectorPDF aggiunge azioni all'app Comandi Rapidi, così puoi usarle nei tuoi comandi rapidi e da Spotlight e Siri.

| Azione | Cosa fa |
| --- | --- |
| Ask About Document | Fa una domanda all'[Agent](agent.md) e restituisce la risposta, con i riferimenti alle pagine |
| Search Document | Trova del testo, come il campo di ricerca, e restituisce ogni corrispondenza con il numero di pagina |
| Extract Pages | Crea un nuovo PDF da alcune pagine di un PDF, come `1-3, 5` |
| Open Document | Apre un documento in VectorPDF, a una pagina se ne indichi una |

Se non scegli un documento per Ask, Search o Extract Pages, l'azione usa il documento in primo piano in VectorPDF.

## Usare un'azione in un comando rapido

1. Apri l'app Comandi Rapidi, quindi crea o apri un comando rapido.
2. Cerca VectorPDF nell'elenco delle azioni, quindi trascina un'azione nel comando rapido.
3. Compila l'azione. Per usare un file di un passaggio precedente del comando rapido, ad esempio quello di un'azione che ottiene un file, fai clic su Document e sceglilo.

Ogni azione passa ciò che restituisce: la risposta, l'elenco delle corrispondenze o il nuovo PDF. Puoi poi inviarlo a un'altra azione, ad esempio una che crea un PDF, aggiunge a una nota o invia un messaggio.

Se le azioni di VectorPDF non compaiono, apri VectorPDF una volta, poi chiudi e riapri Comandi Rapidi.

## Chiedere a Siri

Puoi dire o scrivere queste frasi a Siri. Siri chiede tutto ciò che le serve, come la tua domanda. Le frasi sono in inglese, perché VectorPDF non è ancora tradotto, quindi funzionano quando Siri è impostata in inglese:

- "Ask VectorPDF about this document"
- "Search this document in VectorPDF"
- "Extract pages in VectorPDF"
- "Open a document in VectorPDF"

Puoi anche trovare le azioni digitandone il nome in Spotlight.

## Informazioni su ogni azione

- **Ask About Document** apre il documento in VectorPDF se non è aperto, dietro la finestra in cui stai lavorando. La domanda e la risposta compaiono anche nel pannello Ask About This Document del documento, così puoi leggere le fonti e fare altre domande. Richiede che l'Agent sia attivo e risponde con il motore scelto in [Scegliere come risponde l'Agent](agent-engines.md). Se non è possibile generare risposte, restituisce i passaggi più pertinenti.
- **Search Document** usa Smart Search e i tuoi [Ignored Search Patterns](search.md#ignore-clutter-in-the-text), con Match Case e Whole Words se li attivi. Restituisce fino a 100 corrispondenze e indica quante sono in tutto. Cerca in un documento aperto così com'è in VectorPDF, con le modifiche non salvate e solo i livelli mostrati; negli altri documenti cerca senza aprirli.
- **Extract Pages** accetta pagine e intervalli separati da virgole. Un intervallo come `5-` arriva all'ultima pagina, e `3-1` restituisce le pagine in ordine inverso. Legge il file come è stato salvato l'ultima volta e non lo modifica. Il nuovo PDF prende il nome dal documento e dalle pagine, ad esempio "Report (Pages 1-3, 5).pdf".
- **Open Document** porta in primo piano il pannello del documento se è già aperto.

Un documento protetto da password deve essere aperto in VectorPDF, con la password inserita, prima che Search Document possa cercarvi. Extract Pages non può usare documenti protetti da password.

> **Nota:** ciò che un'azione restituisce va a Comandi Rapidi o a Siri, e da lì al passaggio successivo del comando rapido. Ask About Document invia solo ciò che l'Agent invierebbe se facessi la domanda in VectorPDF. Consulta [Privacy](privacy.md).

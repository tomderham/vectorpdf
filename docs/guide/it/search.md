<!-- keywords: cercare, ricerca, trova, trova successivo, maiuscole e minuscole, parola intera, ricerca intelligente, schemi ignorati, espressione regolare, tag, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, PDF -->
<!-- source: 9b70f3b5ae8c -->

# Cercare in un documento

## Trovare del testo

1. Premi ⌘F. VectorPDF mostra il pannello Search nella barra laterale.
2. Digita ciò che stai cercando. I risultati compaiono man mano che vengono trovati, a partire dalla pagina in cui ti trovi.

Ogni risultato mostra la pagina e il testo circostante, e ogni corrispondenza viene evidenziata nel documento.

## Spostarsi tra i risultati

| Per | Esegui questa operazione |
| --- | --- |
| Andare al risultato successivo | Premi Return o ⌘G, oppure fai clic sulla freccia giù |
| Andare al risultato precedente | Premi ⇧Return o ⇧⌘G, oppure fai clic sulla freccia su |
| Andare a un risultato qualsiasi | Fai clic su di esso |
| Scorrere l'elenco | Fai clic su un risultato, quindi premi i tasti freccia |

Fai clic con il tasto destro su un risultato per [creare un ancoraggio](anchors.md) o per aprirlo in una nuova finestra.

## Opzioni di ricerca {#search-options}

Fai clic sul pulsante delle opzioni accanto al campo di ricerca:

- **Match Case:** trova solo il testo con le stesse maiuscole e minuscole.
- **Whole Word:** non trova corrispondenze all'interno di parole più lunghe.
- **Smart Search:** è attiva a meno che tu non la disattivi. Spazi, trattini, lineette e interruzioni di riga sono considerati equivalenti, quindi “end-to-end” trova anche “end to end”, persino tra una riga e l'altra. Anche le virgolette dritte e quelle tipografiche sono considerate equivalenti.

## Ignorare gli elementi di disturbo nel testo {#ignore-clutter-in-the-text}

Alcuni documenti inseriscono indicatori all'interno delle frasi, come i numeri delle citazioni, che impediscono di trovare una frase. Smart Search può ignorarli.

1. Scegli VectorPDF > Settings.
2. Accanto a Ignored Search Patterns, fai clic su Edit.
3. Aggiungi uno degli schemi predefiniti o una tua espressione regolare, e attivalo.

Gli schemi predefiniti coprono le citazioni numeriche come [12], i simboli di marchio registrato, la paginazione con asterisco come *123 e i tag di commento IEEE 802.11.

## Documenti scansionati

Le pagine scansionate non contengono testo da cercare finché non vengono riconosciute. Consulta [Cercare nelle pagine scansionate con l'OCR](scanned-pages.md).

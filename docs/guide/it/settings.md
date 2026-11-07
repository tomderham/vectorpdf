<!-- keywords: impostazioni, preferenze, opzioni, aggiornamenti, aggiornamento, verifica aggiornamenti, browser, autore, autore annotazioni, spazio, spazio su disco, cancellare, rimuovere dati, eliminare dati, disinstallare, settings, preferences, options, updates, update, check for updates, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->
<!-- source: 91c5b0e9ab3d -->

# Impostazioni

Scegli VectorPDF > Settings oppure premi ⌘,.

| Impostazione | Funzione |
| --- | --- |
| Annotation Author | Il nome salvato sulle tue annotazioni e risposte. Se è vuoto, VectorPDF usa il tuo nome utente del Mac. |
| Use Agent | Mostra il pannello [Ask About This Document](agent.md) nella barra laterale, su macOS 26 o versioni successive. |
| AI Synthesis Engine | Sceglie [cosa scrive le risposte dell'Agent](agent-engines.md), su macOS 27. |
| PDF Color | Imposta [l'aspetto delle pagine](pdf-colors.md): Follow System, Light, Dark o Sepia. |
| Open Links In | Sceglie il browser per i link web. |
| LaTeX (SyncTeX) | Sceglie l'editor che apre il [sorgente LaTeX](latex.md) quando fai clic su un PDF tenendo premuti ⇧⌘. |
| Ignored Search Patterns | Elenca il testo che [Smart Search ignora](search.md#ignore-clutter-in-the-text). |
| Digital Stamp | Crea, modifica o elimina il tuo [timbro](stamps.md). |
| Sync reading positions with iCloud | Mantiene [pagina, zoom, ancore](reading-positions.md) e [ricerche recenti](search.md) sugli altri tuoi Mac. |
| Storage | Mostra quanto spazio occupano i dati di VectorPDF e permette di [cancellarli](#free-up-space-or-remove-data). |
| Automatically check for updates | Cerca una nuova versione su GitHub circa una volta al giorno. Fai clic su Check Now per controllare in qualsiasi momento. |

## Liberare spazio o rimuovere i dati {#free-up-space-or-remove-data}

In Storage, le impostazioni mostrano quanto spazio occupa ogni tipo di dati:

- **Indici dell'Agent:** ciò che l'Agent crea per rispondere alle domande su un documento. Fai clic su Clear per eliminarli; il documento viene indicizzato di nuovo la prossima volta che usi l'Agent con esso. VectorPDF li mantiene sotto i 500 MB eliminando prima quelli usati meno di recente, ed elimina l'indice di un documento quando il documento non esiste più.
- **Cronologia di lettura:** l'ultima pagina, lo zoom, le ancore e le ricerche recenti di ogni documento. Fai clic su Clear per dimenticarli, su questo Mac e in iCloud.
- **File temporanei:** copie create durante la modifica, il salvataggio, la stampa o l'esportazione, e gli aggiornamenti scaricati. VectorPDF elimina quelli rimasti alla successiva apertura.

Per rimuovere tutto ciò che VectorPDF ha memorizzato, fai clic su Remove All VectorPDF Data. Vengono rimossi anche impostazioni, preferiti, gruppi di pannelli, timbro e chiavi API, poi VectorPDF si chiude. I tuoi documenti non vengono toccati. Prima salva o chiudi i documenti con modifiche non salvate.

## Aggiornare VectorPDF

Scegli VectorPDF > Check for Updates. Se è disponibile una nuova versione, fai clic su Download. Al termine del download, fai clic su **Quit and Open Installer**, quindi trascina VectorPDF nella cartella Applicazioni.

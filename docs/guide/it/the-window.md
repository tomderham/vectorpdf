<!-- keywords: finestra, barra degli strumenti, barre degli strumenti, barra laterale, pannelli, schermata Start, interfaccia, indicatore di pagina, controlli, allegati, window, toolbar, toolbars, sidebar, tabs, start screen, interface, page indicator, controls, attachments, barra di stato, Inspector, status bar -->
<!-- source: 52234d6db490 -->

# La finestra di VectorPDF

Ogni finestra di VectorPDF ha una barra degli strumenti, una barra laterale e il documento stesso. Le finestre possono contenere più documenti come [pannelli](tabs-and-windows.md).

## Barra degli strumenti

| Controllo | Funzione |
| --- | --- |
| Titolo del documento | Mostra il nome del documento. Fai clic su di esso con il tasto destro per Favorites e Tab Groups. |
| Zoom | I pulsanti − e + modificano lo zoom a passi. Fai clic sulla percentuale per digitare un valore. |
| Rotate Left e Rotate Right | Ruotano la vista. Il PDF salvato non viene modificato. |
| Two-Page Mode | Mostra le pagine affiancate, come un libro aperto. |
| Horizontal Scrolling | Dispone le pagine da sinistra a destra, quante ne entrano nella finestra. |
| Markup Toolbar | Mostra gli [strumenti di annotazione](text-markup.md). |
| Measurement Toolbar | Mostra gli [strumenti di misurazione](measure.md). |
| Page | Le frecce spostano di una pagina alla volta. Fai clic sul numero di pagina per digitare la pagina desiderata. |

Consulta [Zoom, rotazione e layout di pagina](zoom-and-layout.md) per ulteriori informazioni su questi controlli.

## Barra laterale

I pannelli nella parte superiore della barra laterale consentono di passare tra:

- **Outline & Thumbnails:** l'[indice o una miniatura di ogni pagina](outline-and-thumbnails.md).
- **Search:** i [risultati per il documento corrente](search.md). Puoi spostare Search sul lato destro della finestra, per vederla [accanto alla struttura](search.md#see-results-beside-the-outline).
- **Anchors:** [i punti che hai salvato](anchors.md).
- **Document:** ciò che il documento contiene oltre alle pagine: i suoi [livelli](layers.md), i suoi [allegati](attachments.md), le sue [firme digitali](digital-signatures.md) e, se li attivi nelle Impostazioni, i suoi [campi modulo, link e destinazioni](document-tab.md). Scegli cosa mostrare dal menu in cima al pannello. Questo pannello compare solo quando il documento ne ha almeno uno.
- **Comments:** [tutte le annotazioni, con le risposte e lo stato](draw-and-notes.md#see-all-annotations).
- **Ask About This Document:** [l'Agent](agent.md). Questo pannello compare su macOS 26 o versioni successive, a meno che tu non abbia disattivato [Use Agent](settings.md) in Settings.

Usa il pulsante della barra laterale nella barra degli strumenti per mostrare o nascondere la barra laterale. VectorPDF ricorda, per ogni documento, se l’hai mostrata o nascosta. La prima volta che apri un documento, la barra laterale viene mostrata, a meno che il documento non abbia solo una o due pagine e niente per la barra laterale: né indice, né livelli, annotazioni o allegati. Un documento breve con allegati o livelli si apre sul pannello Document che li mostra, e uno con annotazioni sul pannello Comments.

## Barre degli strumenti aggiuntive

Tre barre degli strumenti compaiono sotto la barra principale quando ti servono. Sceglile dal menu View:

- **Markup** (⇧⌘A) contiene gli [strumenti di annotazione](text-markup.md).
- **Measurement** (⇧⌘M) contiene gli [strumenti di misurazione](measure.md).
- **Redact** (⌥⌘R) contiene gli [strumenti di oscuramento](redact.md).

Il menu View può anche mostrare una barra di stato sotto la pagina, i righelli, una griglia, l’Inspector accanto alla pagina e un navigatore nell’angolo. Consulta [Righelli, barra di stato e Inspector](rulers-and-inspector.md).

## Menu di scelta rapida

Molti comandi sono disponibili anche nei menu che compaiono quando fai clic con il tasto destro, oppure tenendo premuto il tasto Control, sul documento, sulla barra laterale o sulla barra degli strumenti. Consulta [Menu di scelta rapida](right-click-menus.md).

## Indicatore di pagina

Quando cambi pagina, sul documento compare per un momento un piccolo indicatore di pagina, con le frecce per passare alla pagina precedente e a quella successiva. Mentre è visibile la barra degli strumenti Measurement, mostra anche la scala di disegno della pagina.

## Schermata Start

Una finestra o un pannello vuoti mostrano la schermata Start, con l'area di rilascio e poi Tab Groups, Favorites e Recent Documents. Fai clic su una riga per aprirla. Tieni il puntatore su una riga e fai clic sul pulsante •••, oppure fai clic con il tasto destro sulla riga, per aprirla in un nuovo pannello o in una nuova finestra, mostrarla nel Finder o rimuoverla.

La schermata Start elenca fino a tre Tab Groups e cinque Favorites. Il menu Favorites li elenca tutti.

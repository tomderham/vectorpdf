<!-- keywords: pannello Document, campi modulo, campi, firme, firmato, firma digitale, certificato, link, collegamenti ipertestuali, URL, link web, destinazioni con nome, destinazioni, contenuto, barra laterale, document tab, form fields, fields, signatures, signed, digital signature, certified, links, hyperlinks, web links, named destinations, contents, sidebar -->
<!-- source: e2c42440bfd7 -->

# Campi modulo, firme, link e destinazioni

Il pannello Document (una scatola) in cima alla barra laterale elenca ciò che un documento contiene oltre alle pagine. Scegli cosa mostra dal menu in cima al pannello:

- **Layers:** consulta [Mostrare e nascondere i livelli](layers.md).
- **Attachments:** consulta [File allegati a un PDF](attachments.md).
- **Form Fields:** ogni campo di un modulo, con il suo valore, e le sue firme.
- **Links:** ogni link, con il testo su cui si trova e dove porta.
- **Destinations:** i punti con nome del documento a cui i link possono puntare.

Form Fields, Links e Destinations vengono elencati solo se attivi **List form fields, links and destinations in the sidebar** in VectorPDF > Settings > General. Quasi tutti i documenti contengono link, quindi altrimenti il pannello comparirebbe per quasi tutti.

Il menu offre solo ciò che il documento contiene, e il pannello compare solo quando ne contiene almeno uno.

## Campi modulo e firme

I campi sono elencati pagina per pagina, con il nome che il modulo dà loro. Ognuno mostra il suo valore e **Required** quando il modulo indica che va compilato. Tieni il puntatore su un campo per vederne il nome completo e il tipo. Fai clic su un campo per raggiungerlo nella pagina; viene evidenziato per un momento. Per compilare i campi, consulta [Compilare i moduli](forms.md). L’elenco mostra i nuovi valori mentre scrivi.

Un campo firma mostra chi l’ha firmato e quando, come registrato dalla firma, oppure **Not signed**. Indica anche se il file è stato salvato di nuovo dopo la firma, il che può modificare ciò che è stato firmato, e se la firma certifica il documento e quali modifiche consente.

> **Nota:** VectorPDF non controlla il certificato della firma, quindi non può dirti se una firma è valida. Per questo, usa un programma che convalida le firme, come Adobe Acrobat Reader.

## Link

I link sono elencati pagina per pagina, appena ogni pagina viene letta, così i primi link di un documento lungo compaiono subito. Usa i pulsanti sopra l’elenco per mostrare **All** i link, solo quelli **Web** o quelli **In Document**, e scrivi in **Filter** per trovare un link dal suo testo o indirizzo.

| Per | Fai così |
| --- | --- |
| Mostrare un link nella sua pagina | Fai clic sul link |
| Seguire un link | Fai doppio clic sul link. Un link web si apre nel browser. |
| Copiare un indirizzo web | Fai clic con il tasto destro sul link, poi scegli Copy Address |

## Destinazioni

Le destinazioni sono punti con nome di un documento, come `section.2` o `figure.3`. LaTeX e altri programmi le creano perché i link possano puntarvi. Fai clic su una destinazione per raggiungerla. Per copiarne il nome, fai clic con il tasto destro e scegli Copy Name.

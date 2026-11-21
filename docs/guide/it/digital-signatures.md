<!-- keywords: verificare le firme digitali, marca temporale, server di marcatura temporale, certificare, bloccare i campi, firma digitale, firme digitali, firmare, firmare con certificato, certificato, portachiavi, firmato, firmatario, certificazione, valida, non valida, verificare, convalidare, attendibilità, identità, manomesso, modificato, digital signature, digital signatures, sign, signing, sign with certificate, p12, pfx, keychain, signed, signer, certificate, certified, certification, valid, invalid, verify, validate, trust, identity, timestamp, PKCS, CAdES, PAdES, tampered, changed, check signature -->
<!-- source: b817ac7da979 -->

# Verificare le firme digitali

Una firma digitale mostra chi ha firmato un documento e che da allora non è cambiato. Per firmare un PDF con un tuo certificato, consulta [Firmare con un certificato](stamps.md#sign). Quando apri un PDF firmato, VectorPDF ne verifica le firme e mostra ciò che ha trovato in una barra sopra la pagina:

- **La firma è valida:** il documento non è cambiato da quando è stato firmato, e il certificato del firmatario è stato emesso da un’autorità di cui il tuo Mac si fida.
- **L’identità del firmatario non è verificata su questo Mac:** il documento non è cambiato, ma niente garantisce chi l’ha firmato. Consulta [Perché l’identità di un firmatario può non essere verificata](#signer-identity).
- **Non valida:** il documento è stato modificato dopo la firma, oppure la firma non corrisponde al documento.

Fai clic su **Signature Details** per vedere ogni firma nel pannello Document della barra laterale. Per nascondere la barra, fai clic sul suo pulsante di chiusura.

> **Nota:** una [firma autografa](stamps.md) è l'immagine di una firma, non una firma digitale.

## Cosa verifica VectorPDF

Per ogni firma, l’elenco nel pannello Document mostra:

- Se le parti del file che ha firmato sono esattamente come quando sono state firmate.
- Se il file è stato salvato di nuovo dopo la firma, e se quelle modifiche sono tra quelle che la firma consente. Compilare campi modulo, aggiungere firme e aggiungere o modificare annotazioni di solito è consentito. Una firma di certificazione può consentire meno modifiche. Se dopo la firma sono state aggiunte annotazioni, l’elenco lo indica: un’annotazione può coprire ciò che è stato firmato.
- Chi l’ha firmata, con il nome nel suo certificato, e chi ha emesso il certificato. Viene mostrato anche il nome che il software di firma ha scritto nel documento, quando è diverso.
- Quando è stata firmata. Un’ora fornita da un’autorità di marcatura temporale è garantita se la marca è di questa firma e il tuo Mac si fida della sua autorità; altrimenti l’elenco indica perché non conta. Un’ora presa dal computer del firmatario non è garantita. Il certificato del firmatario viene verificato com’era al momento della marca temporale o, se manca, com’è adesso: una firma senza marca temporale smette quindi di risultare verificata quando il suo certificato scade.
- Il motivo e il luogo indicati dal firmatario, se presenti.

Fai clic su una firma per andare a essa nella pagina. Per vederne i certificati, fai clic su **Show Certificate**, oppure fai clic con il tasto destro sulla firma e scegli Show Certificate.

VectorPDF verifica il file così come è stato salvato l’ultima volta, quindi le modifiche non salvate non sono incluse. Ripete la verifica a ogni salvataggio.

## Perché l’identità di un firmatario può non essere verificata {#signer-identity}

Chiunque può creare un certificato con qualsiasi nome. Una firma dimostra chi ha firmato solo se il certificato è stato emesso da un’autorità che ne ha verificato l’identità, e il tuo Mac si fida di quell’autorità. VectorPDF usa i certificati di cui il tuo Mac si fida, in Accesso Portachiavi.

Molti PDF firmati usano certificati di autorità di cui Adobe Acrobat si fida ma macOS no, quindi VectorPDF indica i loro firmatari come non verificati. Il documento può comunque essere invariato da quando è stato firmato. Per fidarti di un’autorità, aggiungi il suo certificato ad Accesso Portachiavi e impostalo su “Fidati sempre”, ma solo se sei sicuro che sia quello autentico.

VectorPDF non si collega a internet per verificare se un certificato è stato revocato. Così nessuno viene a sapere che hai aperto il documento.

## Salvare un documento firmato

Quando salvi un documento firmato, VectorPDF aggiunge le tue modifiche dopo la parte firmata del file e lascia quella parte com’era, così le firme restano valide nella misura in cui le modifiche sono consentite. Rimuovere contenuti con l’[oscuramento](redact.md) riscrive l’intero file, quindi le firme del documento non sono più valide.

## Tipi di firma verificati

VectorPDF verifica le firme PDF più comuni: firme PKCS #7 e CAdES (PAdES). Non verifica ancora le marche temporali del documento né le vecchie firme X.509 RSA. Sono elencate come **Not checked**.

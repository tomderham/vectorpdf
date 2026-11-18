<!-- keywords: firma digitale, firme digitali, firmare, firmare con certificato, certificato, portachiavi, firmato, firmatario, certificato, certificazione, valida, non valida, verificare, convalidare, attendibilità, identità, marca temporale, manomesso, modificato, digital signature, digital signatures, sign, signing, sign with certificate, p12, pfx, keychain, signed, signer, certificate, certified, certification, valid, invalid, verify, validate, trust, identity, timestamp, PKCS, CAdES, PAdES, tampered, changed -->
<!-- source: 3d32c92200ad -->

# Firmare e verificare le firme digitali

Una firma digitale mostra chi ha firmato un documento e che da allora non è cambiato. Puoi [firmare un PDF](#sign) con un tuo certificato. Quando apri un PDF firmato, VectorPDF ne verifica le firme e mostra cosa ha trovato in una barra sopra la pagina:

- **La firma è valida:** il documento non è cambiato da quando è stato firmato, e il certificato del firmatario è stato emesso da un’autorità di cui il tuo Mac si fida.
- **L’identità del firmatario non è verificata su questo Mac:** il documento non è cambiato, ma niente garantisce chi l’ha firmato. Consulta [Perché l’identità di un firmatario può non essere verificata](#signer-identity).
- **Non valida:** il documento è stato modificato dopo la firma, oppure la firma non corrisponde al documento.

Fai clic su **Signature Details** per vedere ogni firma nel pannello Document della barra laterale. Per nascondere la barra, fai clic sul suo pulsante di chiusura.

> **Nota:** un [timbro](stamps.md) è l’immagine di una firma, non una firma digitale.

## Firmare con un certificato {#sign}

Per firmare ti serve un certificato di firma con la sua chiave privata. La tua organizzazione o un’autorità di certificazione può fornirtene uno, di solito come file .p12 o .pfx con una password. I certificati nel tuo portachiavi si possono usare direttamente.

1. Scegli Edit > Sign with Certificate, quindi fai clic sulla pagina nel punto in cui deve andare la firma. Premi Esc per smettere. Se il documento ha un campo firma vuoto, puoi invece fare clic sul campo e scegliere Sign with Certificate.
2. Scegli il tuo certificato. Per usare un file, fai clic su **Choose Certificate File**, quindi digita la sua password. Il file viene letto solo per questa firma e non viene aggiunto al tuo portachiavi.
3. Se vuoi, digita un motivo (ad esempio “Approvo questo documento”) e il luogo in cui firmi. Se hai creato un [timbro](stamps.md), puoi mostrare la tua firma autografa nel campo. Altrimenti viene mostrato il tuo nome.
4. Fai clic su **Sign**.

Firmare salva il documento, quindi se ci sono modifiche non salvate VectorPDF ti chiede prima di salvarle. Entrano a far parte di ciò che firmi. macOS potrebbe chiederti di consentire a VectorPDF di usare la chiave del tuo certificato.

La firma lascia gli altri campi modulo del documento come erano, così altre persone possono ancora compilarli, firmare a loro volta o aggiungere annotazioni senza rendere non valida la tua firma. Ogni firma successiva viene aggiunta dopo le precedenti nello stesso modo.

La firma è una firma PKCS #7 con SHA-256 che contiene il tuo certificato e quelli delle autorità che lo hanno emesso. Registra l’ora del tuo Mac. Non ha ancora una marca temporale di un’autorità di marcatura temporale.

## Cosa verifica VectorPDF

Per ogni firma, l’elenco nel pannello Document mostra:

- Se le parti del file che ha firmato sono esattamente come quando sono state firmate.
- Se il file è stato salvato di nuovo dopo la firma, e se quelle modifiche sono tra quelle che la firma consente. Compilare campi modulo, aggiungere firme e aggiungere o modificare annotazioni di solito è consentito. Una firma di certificazione può consentire meno modifiche. Se dopo la firma sono state aggiunte annotazioni, l’elenco lo indica: un’annotazione può coprire ciò che è stato firmato.
- Chi l’ha firmata, con il nome nel suo certificato, e chi ha emesso il certificato. Viene mostrato anche il nome che il software di firma ha scritto nel documento, quando è diverso.
- Quando è stata firmata. Un’ora fornita da un’autorità di marcatura temporale è garantita. Un’ora presa dal computer del firmatario no.
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

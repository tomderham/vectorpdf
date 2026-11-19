<!-- keywords: firma autografa, firma, firmare, timbro, timbri, firme, iniziali, stamp, stamps, signature, signatures, sign, signing, initials, PDF, handwritten signature, digital signature, sign with certificate, certificate, p12, pfx, keychain, timestamp, certify, lock fields, which signature -->
<!-- source: b94ff6b8a43e -->

# Firmare un documento

Ci sono due modi per firmare, e fanno cose diverse. Entrambi si trovano nel pulsante Sign, la firma nella barra degli strumenti Markup (⇧⌘A).

| | Firma autografa | Firma digitale |
| --- | --- | --- |
| Che cos'è | Un'immagine della tua firma o delle tue iniziali sulla pagina | Una firma fatta con il tuo certificato e conservata nel file |
| Mostra chi ha firmato | No: chiunque può incollare un'immagine | Sì, quando il certificato proviene da un'autorità di cui il lettore si fida |
| Mostra che il documento non è cambiato da allora | No | Sì |
| Che cosa serve | Niente: disegna, digita o scegli un'immagine | Un certificato per firmare, dalla tua organizzazione o da un'autorità di certificazione |
| Si può togliere in seguito | Sì, come un commento | Solo tornando a una copia salvata prima della firma |

Una firma autografa basta dove è sufficiente un'immagine, come in un modulo informale. Usa una firma digitale per contratti, approvazioni e tutto ciò che qualcuno potrebbe dover verificare in seguito. Una firma digitale può anche mostrare la tua firma autografa nel suo riquadro.

## Aggiungere la firma autografa {#add-your-handwritten-signature}

1. Mostra la barra degli strumenti Markup (⇧⌘A), fai clic sul pulsante Sign, quindi scegli Add Handwritten Signature. La prima volta, VectorPDF ti chiede di creare la tua firma:
   - **Draw:** firma con il trackpad o il mouse.
   - **Type:** inserisci il tuo nome o le tue iniziali e scegli un font.
   - **Image:** scegli un file PNG o JPEG. Se scegli **Transparent background**, la pagina si vede attraverso lo sfondo dell'immagine.
2. Fai clic dove la vuoi.

Quindi trascinala per spostarla, oppure trascina un angolo per ridimensionarla. Per rimuoverla, selezionala e premi Delete, oppure fai clic su di essa con il tasto destro e scegli Delete Signature.

VectorPDF conserva la tua firma su questo Mac per la volta successiva. Per modificarla o eliminarla, scegli VectorPDF > Settings, fai clic su General, quindi usa i pulsanti accanto a Handwritten Signature.

## Firmare con un certificato {#sign}

Per firmare ti serve un certificato di firma con la sua chiave privata. La tua organizzazione o un’autorità di certificazione può fornirtene uno, di solito come file .p12 o .pfx con una password. I certificati nel tuo portachiavi si possono usare direttamente.

1. Fai clic sul pulsante Sign nella barra degli strumenti Markup e scegli Sign with Certificate, oppure scegli Edit > Sign with Certificate. Quindi trascina un riquadro sulla pagina dove deve andare la firma, oppure fai clic per uno della dimensione abituale. Premi Esc per interrompere. Se il documento ha un campo firma vuoto, puoi invece fare clic sul campo e scegliere Sign with Certificate.
2. Scegli il tuo certificato. Un’anteprima mostra come apparirà la firma. Per usare un file, fai clic su **Choose Certificate File**, quindi digita la sua password. Il file viene letto solo per questa firma e non viene aggiunto al tuo portachiavi.
3. Se vuoi, inserisci un motivo (ad esempio «Approvo questo documento») e il luogo in cui firmi. Se hai creato una [firma autografa](#add-your-handwritten-signature), puoi mostrarla nel campo. Altrimenti viene mostrato il tuo nome.
4. Se vuoi, scegli in After Signing:
   - **Certify**, se nessuno ha ancora firmato il documento: indica quali modifiche lo lasciano valido d’ora in poi: compilare moduli, firmare e aggiungere annotazioni; compilare moduli e firmare; oppure nessuna. Un documento certificato appare come tale a chiunque lo verifichi, e le modifiche successive che non consente rendono non valida la tua firma.
   - **Lock form fields**, per un modulo: tutti i suoi campi, o quelli che scegli, diventano di sola lettura e mantengono i valori che hai firmato.
5. Fai clic su **Sign**.

Firmare salva il documento, quindi se ci sono modifiche non salvate VectorPDF ti chiede prima di salvarle. Entrano a far parte di ciò che firmi. macOS potrebbe chiederti di consentire a VectorPDF di usare la chiave del tuo certificato.

A meno che tu non li blocchi o certifichi il documento per meno, la firma lascia gli altri campi modulo del documento come erano, così altre persone possono ancora compilarli, firmare a loro volta o aggiungere annotazioni senza rendere non valida la tua firma. Ogni firma successiva viene aggiunta dopo le precedenti nello stesso modo.

La firma è una firma PKCS #7 con SHA-256 che contiene il tuo certificato e quelli delle autorità che lo hanno emesso. Registra l’ora del tuo Mac.

Perché un server di marcatura temporale garantisca quando hai firmato, attiva **Add a timestamp** e indica il suo indirizzo (la tua organizzazione potrebbe averne uno; ne esistono di gratuiti, come quello di DigiCert, `http://timestamp.digicert.com`). Con una marca temporale, la tua firma può essere verificata com’era al momento della firma, anche dopo la scadenza del tuo certificato. Il server riceve solo un’impronta della firma, nulla del documento. Se non è raggiungibile, non viene firmato nulla e il documento resta com’era.

Per verificare le firme di un documento, consulta [Verificare le firme digitali](digital-signatures.md).

## Firmare un modulo

Se un modulo ha un campo firma, fai clic su **Sign** nel campo, quindi scegli Add Handwritten Signature o Sign with Certificate. Consulta [Compilare i moduli](forms.md).

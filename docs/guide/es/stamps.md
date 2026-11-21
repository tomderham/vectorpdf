<!-- keywords: firma manuscrita, firma, firmar, sello, sellos, firmas, iniciales, stamp, stamps, signature, signatures, sign, signing, initials, PDF, handwritten signature, digital signature, sign with certificate, certificate, p12, pfx, keychain, timestamp, certify, lock fields, which signature -->
<!-- source: 132d42959c5b -->

# Firmar un documento

Hay dos formas de firmar, y hacen cosas distintas. Ambas están en el botón Sign, la firma de la barra de herramientas Markup (⇧⌘A).

| | Firma manuscrita | Firma digital |
| --- | --- | --- |
| Qué es | Una imagen de tu firma o tus iniciales en la página | Una firma hecha con tu certificado y guardada en el archivo |
| Muestra quién firmó | No: cualquiera puede pegar una imagen | Sí, cuando el certificado procede de una autoridad en la que confía el lector |
| Muestra que el documento no ha cambiado desde entonces | No | Sí |
| Qué necesitas | Nada: dibuja, escribe o elige una imagen | Un certificado para firmar, de tu organización o de una autoridad de certificación |
| Se puede quitar después | Sí, como un comentario | Solo volviendo a una copia guardada antes de firmar |

Una firma manuscrita basta cuando sirve una imagen, como en un formulario informal. Usa una firma digital para contratos, aprobaciones y todo lo que alguien pueda necesitar comprobar más adelante. Una firma digital también puede mostrar tu firma manuscrita en su recuadro.

## Añadir tu firma manuscrita {#add-your-handwritten-signature}

1. Muestra la barra de herramientas Markup (⇧⌘A), haz clic en el botón Sign y luego elige Add Handwritten Signature. La primera vez, VectorPDF te pide que crees tu firma:
   - **Draw:** firma con el trackpad o el ratón.
   - **Type:** escribe tu nombre o tus iniciales y elige una fuente.
   - **Image:** elige un archivo PNG o JPEG. Si eliges **Transparent background**, la página se ve a través del fondo de la imagen.
2. Haz clic donde la quieras.

Después, arrástrala para moverla, o arrastra una esquina para cambiar su tamaño. Para quitarla, selecciónala y pulsa Delete, o haz clic en ella con el botón derecho y elige Delete Signature.

VectorPDF guarda tu firma en este Mac para la próxima vez. Para cambiarla o eliminarla, elige VectorPDF > Settings, haz clic en General y usa los botones junto a Handwritten Signature.

## Firmar con un certificado {#sign}

Para firmar necesitas un certificado de firma con su clave privada. Tu organización o una autoridad de certificación pueden darte uno, normalmente como archivo .p12 o .pfx con una contraseña. Los certificados de tu llavero se pueden usar directamente.

1. Haz clic en el botón Sign de la barra de herramientas Markup y elige Sign with Certificate, o elige Edit > Sign with Certificate. Luego arrastra un recuadro en la página donde deba ir la firma, o haz clic para uno del tamaño habitual. Pulsa Esc para parar. Si el documento tiene un campo de firma vacío, puedes hacer clic en el campo y elegir Sign with Certificate.
2. Elige tu certificado. Una vista previa muestra cómo se verá la firma. Para usar un archivo, haz clic en **Choose Certificate File** y escribe su contraseña. El archivo se lee solo para esta firma y no se añade a tu llavero.
3. Si quieres, escribe un motivo (como «Apruebo este documento») y dónde estás firmando. Si has creado una [firma manuscrita](#add-your-handwritten-signature), puedes mostrarla en el campo. Si no, se muestra tu nombre.
4. Si quieres, elige en After Signing:
   - **Certify**, si nadie ha firmado aún el documento: indica qué cambios lo mantienen válido a partir de ahora: rellenar formularios, firmar y añadir anotaciones; rellenar formularios y firmar; o ninguno. Un documento certificado aparece como certificado para cualquiera que lo compruebe, y los cambios posteriores que no permite invalidan tu firma.
   - **Lock form fields**, en un formulario: todos sus campos, o los que elijas, pasan a ser de solo lectura y conservan los valores que firmaste.
5. Haz clic en **Sign** y elige dónde guardar el documento firmado. VectorPDF propone una copia junto al original, con “(signed)” al final del nombre, y deja el original sin firmar; después, la copia firmada se abre en su lugar. Para firmar el propio original, elígelo en su lugar y haz clic en **Replace**.

Una firma se hace sobre el documento tal como está guardado, así que firmar siempre guarda. Si el documento tiene cambios sin guardar, VectorPDF te pregunta primero si quieres guardarlos; pasan a formar parte de lo que firmas. Es posible que macOS te pida permitir que VectorPDF use la clave de tu certificado.

Una firma no se puede quitar de un archivo firmado: está ahí para que cualquiera pueda saber que el documento no ha cambiado desde entonces. Si firmas una copia, conservas el original sin firmar para volver a firmarlo o modificarlo.

Salvo que los bloquees o certifiques el documento para menos, la firma deja los demás campos de formulario del documento como estaban, para que otras personas puedan seguir rellenándolos, firmar también o añadir anotaciones sin invalidar tu firma. Cada firma posterior se añade después de las anteriores de la misma manera.

La firma es una firma PKCS #7 con SHA-256 que incluye tu certificado y los de las autoridades que lo emitieron. Registra la hora de tu Mac.

Para que un servidor de sellado de tiempo garantice cuándo firmaste, activa **Add a timestamp** e indica su dirección (tu organización puede tener uno; hay gratuitos, como el de DigiCert, `http://timestamp.digicert.com`). Con un sello de tiempo, tu firma puede comprobarse tal como era al firmar, incluso después de que caduque tu certificado. El servidor solo recibe una huella de la firma, nada del documento. Una dirección que empieza por `http://` funciona con los servidores públicos de sellado de tiempo conocidos (como los de DigiCert, Sectigo, GlobalSign, Entrust y Apple) y con los servidores de tu red local; para cualquier otro servidor, usa su dirección `https://`. Si no se puede contactar con el servidor, no se firma nada y el documento queda como estaba.

Para comprobar las firmas de un documento, consulta [Comprobar firmas digitales](digital-signatures.md).

## Firmar un formulario

Si un formulario tiene un campo de firma, haz clic en **Sign** en el campo y luego elige Add Handwritten Signature o Sign with Certificate. Consulta [Rellenar formularios](forms.md).

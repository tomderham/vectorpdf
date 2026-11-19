<!-- keywords: comprobar firmas digitales, sello de tiempo, servidor de sellado de tiempo, certificar, bloquear campos, firma digital, firmas digitales, firmar, firmar con certificado, certificado, llavero, firmado, firmante, certificación, válida, no válida, comprobar, verificar, confianza, identidad, manipulado, modificado, digital signature, digital signatures, sign, signing, sign with certificate, p12, pfx, keychain, signed, signer, certificate, certified, certification, valid, invalid, verify, validate, trust, identity, timestamp, PKCS, CAdES, PAdES, tampered, changed, check signature -->
<!-- source: 9299a883126e -->

# Comprobar firmas digitales

Una firma digital muestra quién firmó un documento y que no ha cambiado desde entonces. Para firmar un PDF con un certificado propio, consulta [Firmar con un certificado](stamps.md#sign). Cuando abres un PDF firmado, VectorPDF comprueba sus firmas y muestra lo que encontró en una barra sobre la página:

- **La firma es válida:** el documento no ha cambiado desde que se firmó, y el certificado del firmante lo emitió una autoridad en la que confía tu Mac.
- **La identidad del firmante no está verificada en este Mac:** el documento no ha cambiado, pero nada garantiza quién lo firmó. Consulta [Por qué puede no estar verificada la identidad de un firmante](#signer-identity).
- **No válida:** el documento se modificó después de firmarse, o la firma no coincide con él.

Haz clic en **Signature Details** para ver cada firma en la pestaña Document de la barra lateral. Para ocultar la barra, haz clic en su botón de cerrar.

> **Nota:** Una [firma manuscrita](stamps.md) es una imagen de una firma, no una firma digital.

## Qué comprueba VectorPDF

Para cada firma, la lista de la pestaña Document muestra:

- Si las partes del archivo que firmó están exactamente como cuando se firmaron.
- Si el archivo se volvió a guardar después de firmarse y si esos cambios son de los que la firma permite. Rellenar campos de formulario, añadir firmas y añadir o cambiar anotaciones suele estar permitido. Una firma de certificación puede permitir menos cambios. Si se añadieron anotaciones después de firmar, la lista lo indica: una anotación puede tapar lo que se firmó.
- Quién la firmó, por el nombre de su certificado, y quién emitió el certificado. También se muestra el nombre que el software de firma escribió en el documento cuando es distinto.
- Cuándo se firmó. Una hora de una autoridad de sellado de tiempo está garantizada si el sello es de esta firma y tu Mac confía en su autoridad; si no, la lista indica por qué no cuenta. Una hora del propio ordenador del firmante no está garantizada.
- El motivo y el lugar que indicó el firmante, si los hay.

Haz clic en una firma para ir a ella en la página. Para ver sus certificados, haz clic en **Show Certificate**, o haz clic con el botón derecho en ella y elige Show Certificate.

VectorPDF comprueba el archivo tal como se guardó por última vez, así que no incluye los cambios sin guardar. Vuelve a comprobarlo cada vez que guardas.

## Por qué puede no estar verificada la identidad de un firmante {#signer-identity}

Cualquiera puede crear un certificado con cualquier nombre. Una firma solo demuestra quién firmó si el certificado lo emitió una autoridad que comprobó su identidad y tu Mac confía en esa autoridad. VectorPDF usa los certificados en los que confía tu Mac, en Acceso a Llaveros.

Muchos PDF firmados usan certificados de autoridades en las que confía Adobe Acrobat pero no macOS, así que VectorPDF indica que sus firmantes no están verificados. Aun así, el documento puede no haber cambiado desde que se firmó. Para confiar en una autoridad, añade su certificado a Acceso a Llaveros y configúralo como “Confiar siempre”, pero solo si estás seguro de que es el auténtico.

VectorPDF no se conecta a internet para comprobar si un certificado se ha revocado. Así nadie se entera de que has abierto el documento.

## Guardar un documento firmado

Cuando guardas un documento firmado, VectorPDF añade tus cambios después de la parte firmada del archivo y deja esa parte como estaba, para que las firmas sigan siendo válidas en la medida en que los cambios estén permitidos. Eliminar contenido con la [censura](redact.md) reescribe todo el archivo, así que las firmas del documento dejan de ser válidas.

## Tipos de firma que se comprueban

VectorPDF comprueba las firmas PDF habituales: firmas PKCS #7 y CAdES (PAdES). Todavía no comprueba los sellos de tiempo de documento ni las firmas X.509 RSA antiguas. Aparecen como **Not checked**.

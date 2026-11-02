<!-- keywords: censurar, censura, censuras, eliminar, tachar, ocultar, confidencial, información sensible, número de la Seguridad Social, tarjeta de crédito, correo electrónico, teléfono, fecha, buscar y censurar, metadatos, marcadores, archivos adjuntos, redact, redaction, redactions, remove, black out, sensitive, SSN, credit card, email, phone, date, find and redact, metadata, bookmarks, attachments, PDF -->
<!-- source: d8be777cd6d7 -->

# Censurar contenido confidencial

La censura elimina contenido de un PDF de forma permanente. VectorPDF borra del archivo el texto, los píxeles de imagen y los trazos que hay bajo el área censurada, junto con las anotaciones y los campos de formulario que la tocan. No se limita a taparlos con un recuadro, y las revisiones anteriores no se conservan al guardar.

La primera vez que censuras algo en un documento, una alerta explica qué más cambia:

- **Se elimina de todo el documento:** los metadatos, como el título y el autor, los archivos adjuntos, las miniaturas de página, el texto alternativo para accesibilidad y los datos de formularios XFA. Para conservarlos, censura una copia.
- **Los marcadores se mantienen,** y cada palabra censurada de sus títulos se sustituye por [Redacted]. El texto de las imágenes y los escaneados no se puede comparar, así que revisa tú mismo los marcadores después de censurarlos.
- **No se elimina:** los destinos con nombre, las etiquetas de página, los nombres de capa ni el código JavaScript. Podrían seguir conteniendo el texto.

> **Advertencia:** La censura surte efecto en cuanto la aplicas, y no hay Undo. El archivo original no cambia hasta que lo guardas, así que, para empezar de nuevo, cierra el documento sin guardar. Conserva una copia del original y usa Save As para guardar la versión censurada con otro nombre.

Pulsa ⌥⌘R o elige View > Show Redact Toolbar.

## Censurar un área

1. Elige **Redact Region**.
2. Elige Black o White como color de censura.
3. Arrastra sobre el área que quieres censurar.

## Buscar y censurar

1. Elige **Find & Redact**.
2. Elige qué quieres buscar:
   - **Text / Phrase**, con las opciones Match Case y Whole Word.
   - **Custom Regular Expression**, como `[A-Z]{3}-\d{5}`.
   - **Social Security Number (SSN)**, **Credit Card Number**, **Email Address**, **Phone Number** o **Date**. Estas opciones encuentran los formatos habituales automáticamente.
3. Haz clic en Find.
4. Revisa las coincidencias. Haz clic en una para verla en su página, y anula la selección de las que quieras conservar.
5. Elige una acción:
   - **Redact** elimina el contenido y deja un recuadro negro o blanco.
   - **Remove** elimina el contenido sin dejar ningún recuadro.
6. Haz clic en **Redact Selected** o **Remove Selected**.

> **Advertencia:** La detección automática puede pasar cosas por alto, sobre todo formatos poco habituales o texto en imágenes. Revisa el documento antes de compartirlo. El texto de las páginas escaneadas debe censurarse con Redact Region.

## Guardar el resultado

Pulsa ⇧⌘S para guardar el documento censurado con otro nombre. Al guardar también se elimina el índice de búsqueda del [Agent](agent.md) para ese documento, que podría contener el texto eliminado.

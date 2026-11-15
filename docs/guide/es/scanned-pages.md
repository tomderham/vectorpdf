<!-- keywords: OCR, escanear, escaneado, escaneados, escaneos, reconocimiento de texto, reconocer texto, imagen, seleccionar, copiar, resaltar, scan, scanned, scans, text recognition, recognize text, image, Run OCR, select, copy, highlight, PDF con búsqueda, guardar texto, capa de texto, idioma, searchable PDF, save text, text layer, language -->
<!-- source: 8b77a345a44e -->

# Buscar y seleccionar texto en páginas escaneadas

Una página escaneada es una imagen de un texto. VectorPDF puede reconocer el texto mediante reconocimiento óptico de caracteres (OCR), en tu Mac, para que puedas buscar en él, seleccionarlo y marcarlo.

## Cómo funciona

Cuando abres un documento, VectorPDF busca páginas escaneadas entre las 50 primeras y reconoce su texto en segundo plano. Cuando queda más por hacer, la pestaña Search muestra cuántas páginas escaneadas ha encontrado.

- **Para reconocer todas las páginas escaneadas que ha encontrado,** haz clic en **Run OCR** en la pestaña Search.
- Una búsqueda también las reconoce, así que puedes empezar a buscar directamente.

Los resaltados siguen al texto, aunque la página se haya escaneado ligeramente inclinada.

El texto se reconoce en los idiomas de los ajustes Idioma y región de tu Mac que el reconocimiento admite, o en inglés si no admite ninguno.

## Seleccionar texto reconocido

Una vez reconocida una página, puedes [seleccionar y copiar](select-text.md) su texto y [resaltarlo, subrayarlo o tacharlo](text-markup.md) como en cualquier otra página. El reconocimiento puede tardar un momento, y las páginas posteriores a las 50 primeras necesitan antes Run OCR o una búsqueda.

El reconocimiento puede cometer errores, así que comprueba todo lo que copies si tiene que ser exacto. Las selecciones empiezan y terminan limpiamente en los bordes de las palabras. Dentro de una palabra, sus extremos son aproximados.

> **Nota:** El texto reconocido se usa mientras el documento está abierto y no se guarda en el PDF, a menos que decidas guardarlo (consulta más abajo). Las marcas que añades sí se guardan. Si censuras o giras una página, su texto se vuelve a reconocer.

## Guardar el texto reconocido en el PDF {#save-the-recognized-text-in-the-pdf}

Para que un PDF escaneado también se pueda buscar en otras apps, como Vista Previa, Spotlight y Acrobat, guarda en él el texto reconocido. El texto se añade como una capa invisible bajo cada página escaneada, donde se reconoció, así que las páginas se ven igual.

- **Para guardarlo en el documento,** elige File > Save with Recognized Text o haz clic en **Save in PDF** en la pestaña Search cuando su texto esté reconocido. También se guardan tus otros cambios.
- **Para guardarlo en una copia,** elige File > Export Document As > Searchable PDF. El documento que tienes abierto no cambia.

En ambos casos, VectorPDF primero reconoce las páginas escaneadas que aún no ha reconocido y muestra su progreso. Cada página tarda un momento. Puedes hacer clic en Cancel y no se guarda nada.

Solo reciben texto las páginas que no tienen texto propio. Cuando el texto está en el archivo, esas páginas dejan de tratarse como escaneadas: VectorPDF selecciona y busca el texto guardado, como hacen otras apps.

> **Importante:** El reconocimiento puede cometer errores, y el texto guardado va allá donde va el archivo: a índices de búsqueda, texto copiado y lectores de pantalla. Comprueba que el texto es correcto antes de confiar en él, o guarda una copia en su lugar. Guardar el documento también lo vuelve a abrir desde el archivo, así que no puedes deshacer los cambios hechos antes de guardar.

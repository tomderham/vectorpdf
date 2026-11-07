<!-- keywords: exportar, convertir, texto simple, texto, acoplar, acoplado, resumen de anotaciones, optimizar, optimizado, reducir tamaño, comprimir, más pequeño, imágenes, fuentes, contornos, texto a contornos, plóter, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF, optimize, optimized, reduce file size, compress, smaller, downsample, images, fonts, subset, outlines, text to outlines, plotter -->
<!-- source: 6d68e3315dc3 -->

# Exportar a otros formatos

Para exportar un documento completo, elige File > Export Document As y, a continuación, Plain Text, Word Document, Scalable Vector Graphics, Flattened PDF u Optimized PDF. El resumen de anotaciones y las mediciones tienen sus propios comandos.

## Plain Text

Guarda el texto del documento como archivo `.txt`.

## Word Document

Guarda un archivo `.docx` que puedes editar en Word y otras apps. Las disposiciones de página complejas pueden verse diferentes respecto al PDF.

## SVG

Guarda cada página como un archivo Scalable Vector Graphics, con el texto como trazados vectoriales, para que se vea exactamente igual que en el PDF. Un documento de varias páginas se guarda como una carpeta con un archivo por página.

## Flattened PDF {#flattened-pdf}

Guarda un PDF con las anotaciones y los campos de formulario integrados en la página (acoplados), de modo que no se puedan cambiar. En el cuadro de diálogo para guardar, elige qué quieres acoplar:

- **Flatten annotations and markups**
- **Flatten form fields (make static)**

El PDF acoplado solo contiene lo que hay en las [capas](layers.md) que se muestran. Las capas ocultas se omiten con todo lo que contienen, anotaciones incluidas. Las capas que quedan se pueden seguir mostrando y ocultando, y las anotaciones acopladas a la página siguen en sus capas.

> **Nota:** Acoplar no elimina lo que hay debajo. Para eliminar contenido, usa la [censura](redact.md).

## Optimized PDF {#optimized-pdf}

Guarda una copia más pequeña del PDF, incluidos los cambios que aún no hayas guardado. El documento abierto no cambia. Se eliminan los datos que el documento ya no usa, se combinan los duplicados y se comprime todo. En el cuadro de diálogo para guardar, también puedes elegir:

- **Keep only the characters each font uses:** elimina las partes de las fuentes incrustadas que el documento no usa. Activado por omisión.
- **Images:** deja las imágenes como están o redúcelas a 300 ppp (para imprimir) o 150 ppp (para leer en pantalla). Solo se reducen las imágenes con más resolución. Las fotos se guardan como JPEG; los diagramas y las capturas de pantalla se mantienen sin pérdida. Los escaneos en blanco y negro no se modifican.
- **Convert text to outlines:** dibuja cada letra como una forma, para que el documento se vea igual en plóteres, cortadoras y sistemas de impresión que no tienen sus fuentes. El texto de la copia no se puede seleccionar, buscar ni copiar.

Cuánto se reduce la copia depende del documento. Los escaneos y las fotos son los que más se reducen cuando reduces sus imágenes.

## Resumen de anotaciones

Elige File > Export Annotations Summary (⇧⌘E) para guardar una lista de las anotaciones del documento, incluidas las de otras apps, con sus autores, estados y respuestas. De forma predeterminada es un archivo Markdown. Si le pones al archivo la extensión `.csv`, se guarda como hoja de cálculo.

## Mediciones

Para exportar las mediciones, usa la [tabla de mediciones](takeoff.md).

<!-- keywords: pestaña Document, campos de formulario, campos, firmas, firmado, firma digital, certificado, enlaces, hipervínculos, URL, enlaces web, destinos con nombre, destinos, contenido, barra lateral, document tab, form fields, fields, signatures, signed, digital signature, certified, links, hyperlinks, web links, named destinations, destinations, contents, sidebar -->
<!-- source: e2c42440bfd7 -->

# Campos de formulario, firmas, enlaces y destinos

La pestaña Document (una caja) de la parte superior de la barra lateral muestra lo que contiene un documento además de sus páginas. Elige qué muestra en el menú de la parte superior de la pestaña:

- **Layers:** consulta [Mostrar y ocultar capas](layers.md).
- **Attachments:** consulta [Archivos adjuntos a un PDF](attachments.md).
- **Form Fields:** cada campo de un formulario, con su valor, y sus firmas.
- **Links:** cada enlace, con el texto en el que está y adónde lleva.
- **Destinations:** los lugares con nombre del documento a los que pueden apuntar los enlaces.

Form Fields, Links y Destinations solo aparecen cuando activas **List form fields, links and destinations in the sidebar** en VectorPDF > Settings > General. La mayoría de los documentos tienen enlaces, así que, si no, la pestaña aparecería en casi todos.

El menú solo ofrece lo que tiene el documento, y la pestaña solo aparece cuando tiene al menos uno de ellos.

## Campos de formulario y firmas

Los campos se muestran página a página, con el nombre que les da el formulario. Cada uno muestra su valor y **Required** cuando el formulario indica que hay que rellenarlo. Mantén el puntero sobre un campo para ver su nombre completo y su tipo. Haz clic en un campo para ir a él en la página; se resalta un momento. Para rellenar campos, consulta [Rellenar formularios](forms.md). La lista muestra los valores nuevos mientras escribes.

Un campo de firma muestra quién lo firmó y cuándo, según lo registra la firma, o **Not signed**. También indica si el archivo se guardó de nuevo después de firmarse, lo que puede cambiar lo firmado, y si la firma certifica el documento y qué cambios permite.

> **Nota:** VectorPDF no comprueba el certificado de la firma, así que no puede decirte si una firma es válida. Para eso, usa un programa que valide firmas, como Adobe Acrobat Reader.

## Enlaces

Los enlaces se muestran página a página en cuanto se lee cada página, así que los primeros enlaces de un documento largo aparecen enseguida. Usa los botones de encima de la lista para mostrar **All** los enlaces, solo los **Web** o los **In Document**, y escribe en **Filter** para buscar un enlace por su texto o su dirección.

| Para | Haz esto |
| --- | --- |
| Mostrar un enlace en su página | Haz clic en él |
| Seguir un enlace | Haz doble clic en él. Un enlace web se abre en tu navegador. |
| Copiar una dirección web | Haz clic con el botón derecho en el enlace y elige Copy Address |

## Destinos

Los destinos son lugares con nombre de un documento, como `section.2` o `figure.3`. LaTeX y otros programas los crean para que los enlaces apunten a ellos. Haz clic en un destino para ir a él. Para copiar su nombre, haz clic en él con el botón derecho y elige Copy Name.

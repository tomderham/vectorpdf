<!-- keywords: revisar encabezados, editar esquema, añadir marcador, esquema a partir de encabezados, encabezados, crear índice, cambiar nombre, sangrar, esquema, tabla de contenido, índice, contenido, marcadores, miniatura, miniaturas, barra lateral, outline, table of contents, TOC, contents, bookmarks, thumbnail, thumbnails, sidebar, bookmark, add bookmark, edit outline, build outline, headings, generate table of contents, rename, indent, outdent -->
<!-- source: 790ab6f4cee0 -->

# Esquema y miniaturas

Haz clic en la pestaña Outline & Thumbnails en la parte superior de la barra lateral y elige **Outline** o **Thumbnails**.

## Esquema

El esquema es la tabla de contenido del documento, si la tiene. La sección que estás leyendo se resalta a medida que te desplazas. Después de ir a un resultado de búsqueda o seguir un enlace, se resalta la sección en la que está, hasta que vuelvas a desplazarte.

- **Ir a una sección:** haz clic en ella. Su título se desplaza cerca de la parte superior de la ventana, o se queda donde está si ya lo ves.
- **Mostrar u ocultar subsecciones:** haz clic en la flecha que hay junto a una sección.
- **Encontrar una sección:** escribe en el campo “Search outline”. Solo se muestran las secciones que coinciden.
- **Ver dónde están los resultados de búsqueda:** con Search [a la derecha de la ventana](search.md#see-results-beside-the-outline), cada sección muestra cuántos resultados tiene.
- **Tener una sección a mano:** haz clic en ella con el botón derecho para crear un [ancla](anchors.md) o abrirla en una ventana nueva.

## Editar el esquema {#edit-the-outline}

Puedes añadir entradas al esquema de un documento (otras apps pueden llamarlas marcadores) y cambiarles el nombre, moverlas y eliminarlas. Los cambios pasan a formar parte del archivo cuando lo [guardas](save.md).

Para añadir una entrada, ve al lugar al que debe llevar y elige Edit > Add Outline Entry (⌥⌘B). Si has seleccionado texto, la entrada lleva a ese texto y se propone como título. Si no, lleva al principio de la página que estás leyendo. Escribe un título y haz clic en **Add**. Las entradas añadidas así se colocan entre las entradas de nivel superior por orden de página, así que también es la forma de empezar un esquema en un documento que no tiene ninguno.

Para todo lo demás, haz clic con el botón derecho en una entrada:

| Para | Elige |
| --- | --- |
| Añadir una entrada después de esta o dentro de ella | Add Entry After o Add Entry Inside |
| Cambiarle el nombre | Rename |
| Hacer que lleve al texto seleccionado o a la página que estás leyendo | Go Here Instead |
| Moverla entre las entradas de su nivel | Move Up o Move Down |
| Ponerla dentro de la entrada de arriba o sacarla de la entrada en la que está | Indent o Outdent |
| Eliminarla, con las entradas que contiene | Delete Entry |

También puedes arrastrar una entrada para moverla, o soltarla sobre otra entrada para ponerla dentro. Las entradas que contiene se mueven con ella. Mientras el esquema está filtrado con el campo “Search outline”, las entradas no se pueden mover: Move Up, Move Down, Indent y Outdent no aparecen en el menú y no se pueden arrastrar; los demás comandos funcionan. Edit > Undo (⌘Z) deshace los cambios del esquema de uno en uno.

### Crear un esquema a partir de los encabezados

Elige Edit > Build Outline from Headings para crear un esquema con los encabezados del documento. También está en el menú contextual de una entrada del esquema. Primero se abre una lista de los encabezados encontrados: desmarca los que no lo sean, haz clic en un título para cambiarlo y usa los botones de sangría para subir o bajar un encabezado de nivel. Haz clic en la flecha junto a un encabezado para verlo en la página. Después haz clic en **Create Outline**, o en **Replace Outline** si el documento ya tiene uno; Edit > Undo recupera el esquema anterior.

En un PDF etiquetado, los encabezados son los que marcan sus etiquetas. En otros PDF, VectorPDF busca líneas que se distinguen del texto: más grandes, o en negrita donde el texto no lo está. Un estilo más grande es un nivel más alto que uno más pequeño, y los números de sección como 3.2.1 dan los niveles dentro de un mismo estilo. Se omiten los encabezados y pies de página repetidos, los pies de figuras y tablas y las líneas de un índice.

Los estilos de un documento no siempre indican qué líneas son encabezados, así que revisa la lista. No se encuentran los encabezados de las páginas escaneadas, ni siquiera cuando se ha reconocido su texto. En algunos PDF etiquetados, los números de sección se dibujan de forma que no forman parte del texto, y las entradas salen sin ellos.

## Miniaturas

Las miniaturas muestran todas las páginas. Haz clic en una para ir a esa página.

Mantén pulsada la tecla ⌘ para seleccionar varias páginas, o ⇧ para seleccionar un intervalo. Después, arrástralas a una nueva posición, o haz clic con el botón derecho para girarlas, duplicarlas, extraerlas o eliminarlas. Consulta [Reorganizar páginas](pages.md).

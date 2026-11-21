<!-- keywords: buscar, búsqueda, buscar siguiente, mayúsculas y minúsculas, palabra completa, búsqueda inteligente, patrones ignorados, expresión regular, etiquetas, búsquedas recientes, historial de búsqueda, sección, esquema, tabla de contenido, lado derecho, junto al esquema, mover la búsqueda, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, recent searches, search history, section, outline, table of contents, right side, beside the outline, move search, PDF -->
<!-- source: 9e3d931100aa -->

# Buscar en un documento

## Buscar texto

1. Pulsa ⌘F. VectorPDF muestra la pestaña Search en la barra lateral, o a la derecha de la ventana si la [has movido allí](#see-results-beside-the-outline).
2. Escribe lo que buscas. Los resultados aparecen a medida que se encuentran, empezando por la página en la que estás.

Los resultados se muestran por página, cada uno con el texto que lo rodea, y todas las coincidencias se resaltan en el documento. En un documento con [esquema](outline-and-thumbnails.md), los resultados también se agrupan por la sección en la que están. El nombre de la sección se queda en la parte superior de la lista mientras recorres sus resultados. Para ver de qué secciones más amplias forma parte, coloca el puntero sobre él.

## Moverse entre los resultados

| Para | Haz esto |
| --- | --- |
| Ir al resultado siguiente | Pulsa Return o ⌘G, o haz clic en la flecha hacia abajo |
| Ir al resultado anterior | Pulsa ⇧Return o ⇧⌘G, o haz clic en la flecha hacia arriba |
| Ir a cualquier resultado | Haz clic en él |
| Recorrer la lista | Haz clic en un resultado y pulsa las teclas de flecha |

Haz clic con el botón derecho en un resultado para [crear un ancla](anchors.md) a partir de él o abrirlo en una ventana nueva.

## Ver los resultados junto al esquema {#see-results-beside-the-outline}

Para ver los resultados y el esquema a la vez, haz clic en el botón de opciones que hay junto al campo de búsqueda y elige Show Search on Right. La búsqueda pasa al lado derecho de la ventana y la barra lateral muestra el esquema, o las miniaturas de las páginas si el documento no tiene esquema. Cada entrada del esquema con resultados muestra cuántos tiene, y el recuento de la sección del resultado actual aparece resaltado. Una sección con sus subsecciones ocultas cuenta también los resultados que hay en ellas. Haz clic en una entrada del esquema y la lista de resultados se desplaza hasta los resultados de esa sección (o los de sus subsecciones, si no tiene ninguno propio), mientras la página muestra el título de la sección; el resultado actual no cambia hasta que hagas clic en uno.

Cada documento recuerda en qué lado pusiste la búsqueda. Para devolverla a la barra lateral, vuelve a elegir Show Search on Right para desactivarla. Para ocultarla mientras está a la derecha, haz clic en el botón de cerrar (×) que hay a su lado. Para volver a mostrarla, pulsa ⌘F o haz clic en el botón Search de la parte superior de la barra lateral.

La búsqueda comparte el lado derecho con el [Inspector](rulers-and-inspector.md#the-inspector). Cuando los dos están abiertos, cambia de uno a otro con los botones Search e Inspector de la parte superior.

## Volver a buscar algo que ya buscaste

Cada documento recuerda las últimas 10 búsquedas en las que fuiste a un resultado. Para volver a buscar una:

- Haz clic en la lupa del campo de búsqueda y elígela, o
- Con el campo de búsqueda vacío, haz clic en ella en la lista Recent Searches, debajo del campo.

VectorPDF va al resultado más cercano. Para olvidar las búsquedas de un documento, elige Clear Recent Searches en la lupa o haz clic en Clear encima de la lista. Aplicar censuras a un documento también borra sus búsquedas recientes.

## Opciones de búsqueda {#search-options}

Haz clic en el botón de opciones que hay junto al campo de búsqueda:

- **Match Case:** solo encuentra texto con las mismas mayúsculas y minúsculas.
- **Whole Word:** no busca coincidencias dentro de palabras más largas.
- **Smart Search:** está activada a menos que la desactives. Los espacios, guiones, rayas y saltos de línea coinciden entre sí, de modo que “end-to-end” también encuentra “end to end”, incluso en un salto de línea. Las comillas rectas y las tipográficas también coinciden entre sí.
- **Show Search on Right:** mueve la búsqueda de la barra lateral a la derecha de la ventana, para que puedas verla [junto al esquema](#see-results-beside-the-outline).

## Ignorar marcas que interrumpen el texto {#ignore-clutter-in-the-text}

Algunos documentos colocan marcas en medio de las frases, como números de cita, lo que impide encontrar una expresión. Smart Search puede pasarlas por alto.

1. Elige VectorPDF > Settings y haz clic en Advanced.
2. Junto a Ignored Search Patterns, haz clic en Edit.
3. Añade uno de los patrones predefinidos o tu propia expresión regular, y actívalo.

Los patrones predefinidos cubren citas numéricas como [12], símbolos de marca registrada, paginación con asterisco como *123 y etiquetas de comentarios de IEEE 802.11.

## Documentos escaneados

Las páginas escaneadas no tienen texto en el que buscar hasta que se reconocen. Consulta [Buscar y seleccionar texto en páginas escaneadas](scanned-pages.md).

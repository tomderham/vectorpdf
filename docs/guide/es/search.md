<!-- keywords: buscar, búsqueda, buscar siguiente, mayúsculas y minúsculas, palabra completa, búsqueda inteligente, patrones ignorados, expresión regular, etiquetas, búsquedas recientes, historial de búsqueda, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, recent searches, search history, PDF -->
<!-- source: 8a443734fd6b -->

# Buscar en un documento

## Buscar texto

1. Pulsa ⌘F. VectorPDF muestra la pestaña Search en la barra lateral.
2. Escribe lo que buscas. Los resultados aparecen a medida que se encuentran, empezando por la página en la que estás.

Cada resultado muestra su página y el texto que lo rodea, y todas las coincidencias se resaltan en el documento.

## Moverse entre los resultados

| Para | Haz esto |
| --- | --- |
| Ir al resultado siguiente | Pulsa Return o ⌘G, o haz clic en la flecha hacia abajo |
| Ir al resultado anterior | Pulsa ⇧Return o ⇧⌘G, o haz clic en la flecha hacia arriba |
| Ir a cualquier resultado | Haz clic en él |
| Recorrer la lista | Haz clic en un resultado y pulsa las teclas de flecha |

Haz clic con el botón derecho en un resultado para [crear un ancla](anchors.md) a partir de él o abrirlo en una ventana nueva.

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

## Ignorar marcas que interrumpen el texto {#ignore-clutter-in-the-text}

Algunos documentos colocan marcas en medio de las frases, como números de cita, lo que impide encontrar una expresión. Smart Search puede pasarlas por alto.

1. Elige VectorPDF > Settings.
2. Junto a Ignored Search Patterns, haz clic en Edit.
3. Añade uno de los patrones predefinidos o tu propia expresión regular, y actívalo.

Los patrones predefinidos cubren citas numéricas como [12], símbolos de marca registrada, paginación con asterisco como *123 y etiquetas de comentarios de IEEE 802.11.

## Documentos escaneados

Las páginas escaneadas no tienen texto en el que buscar hasta que se reconocen. Consulta [Buscar y seleccionar texto en páginas escaneadas](scanned-pages.md).

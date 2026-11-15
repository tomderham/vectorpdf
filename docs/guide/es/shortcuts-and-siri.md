<!-- keywords: Atajos, Siri, Spotlight, automatización, acción, acciones, preguntar, buscar, extraer páginas, abrir documento, flujo de trabajo, Shortcuts, automation, action, actions, App Intents, ask, search, extract pages, open document, workflow -->
<!-- source: 0598b760c342 -->

# Usar VectorPDF con Atajos y Siri

VectorPDF añade acciones a la app Atajos, para que puedas usarlas en tus propios atajos y desde Spotlight y Siri.

| Acción | Qué hace |
| --- | --- |
| Ask About Document | Hace una pregunta al [Agent](agent.md) y devuelve su respuesta, con citas de página |
| Search Document | Busca texto, como el campo de búsqueda, y devuelve cada coincidencia con su número de página |
| Extract Pages | Crea un PDF nuevo con algunas páginas de un PDF, como `1-3, 5` |
| Open Document | Abre un documento en VectorPDF, en una página si indicas una |

Si no eliges un documento para Ask, Search o Extract Pages, la acción usa el documento que está delante en VectorPDF.

## Usar una acción en un atajo

1. Abre la app Atajos y crea un atajo o abre uno.
2. Busca VectorPDF en la lista de acciones y arrastra una acción a tu atajo.
3. Completa la acción. Para usar un archivo de un paso anterior del atajo, como el de una acción que obtiene un archivo, haz clic en Document y elígelo.

Cada acción pasa lo que devuelve: la respuesta, la lista de coincidencias o el PDF nuevo. Después puedes enviarlo a otra acción, como una que crea un PDF, añade a una nota o envía un mensaje.

Si no aparecen las acciones de VectorPDF, abre VectorPDF una vez y luego sal de Atajos y vuelve a abrirla.

## Preguntar a Siri

Puedes decirle o escribirle estas frases a Siri. Siri te pide lo que necesite, como tu pregunta. Las frases están en inglés, porque VectorPDF aún no está traducido, así que funcionan cuando Siri está en inglés:

- "Ask VectorPDF about this document"
- "Search this document in VectorPDF"
- "Extract pages in VectorPDF"
- "Open a document in VectorPDF"

También puedes encontrar las acciones escribiendo sus nombres en Spotlight.

## Sobre cada acción

- **Ask About Document** abre el documento en VectorPDF si no está abierto, detrás de la ventana en la que trabajas. La pregunta y la respuesta también aparecen en la pestaña Ask About This Document del documento, para que puedas leer las fuentes y hacer preguntas de seguimiento. Necesita el Agent activado y responde con el motor que hayas elegido en [Elegir cómo responde el Agent](agent-engines.md). Si no se pueden generar respuestas, devuelve los pasajes que mejor coinciden.
- **Search Document** usa Smart Search y tus [Ignored Search Patterns](search.md#ignore-clutter-in-the-text), con Match Case y Whole Words si los activas. Devuelve hasta 100 coincidencias e indica cuántas hay en total. Busca en un documento abierto tal como está en VectorPDF, con sus cambios sin guardar y solo las capas visibles; en otros documentos busca sin abrirlos.
- **Extract Pages** admite páginas e intervalos separados por comas. Un intervalo como `5-` llega hasta la última página, y `3-1` da las páginas en orden inverso. Lee el archivo tal como se guardó por última vez y no lo modifica. El PDF nuevo recibe el nombre del documento y las páginas, como "Report (Pages 1-3, 5).pdf".
- **Open Document** trae al frente la pestaña del documento si ya está abierto.

Un documento protegido con contraseña debe estar abierto en VectorPDF, con su contraseña introducida, para que Search Document pueda buscar en él. Extract Pages no puede usar documentos protegidos con contraseña.

> **Nota:** Lo que devuelve una acción va a Atajos o a Siri, y de ahí a lo que haga tu atajo a continuación. Ask About Document solo envía lo que el Agent enviaría cuando preguntas en VectorPDF. Consulta [Privacidad](privacy.md).

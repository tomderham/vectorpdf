<!-- keywords: ajustes, configuración, preferencias, opciones, actualizaciones, actualización, buscar actualizaciones, navegador, autor, autor de anotaciones, almacenamiento, espacio en disco, borrar, eliminar datos, desinstalar, settings, preferences, options, updates, update, check for updates, browser, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->
<!-- source: 91c5b0e9ab3d -->

# Ajustes

Elige VectorPDF > Settings o pulsa ⌘,.

| Ajuste | Qué hace |
| --- | --- |
| Annotation Author | El nombre que se guarda en tus anotaciones y respuestas. Si está vacío, VectorPDF usa tu nombre de usuario del Mac. |
| Use Agent | Muestra la pestaña [Ask About This Document](agent.md) en la barra lateral, en macOS 26 o posterior. |
| AI Synthesis Engine | Elige [qué redacta las respuestas del Agent](agent-engines.md), en macOS 27. |
| PDF Color | Define [el aspecto de las páginas](pdf-colors.md): Follow System, Light, Dark o Sepia. |
| Open Links In | Elige el navegador para los enlaces web. |
| LaTeX (SyncTeX) | Elige el editor que abre el [código LaTeX](latex.md) cuando haces clic con ⇧⌘ en un PDF. |
| Ignored Search Patterns | Muestra la lista de texto que [Smart Search pasa por alto](search.md#ignore-clutter-in-the-text). |
| Digital Stamp | Crea, cambia o elimina tu [sello](stamps.md). |
| Sync reading positions with iCloud | Mantiene tu [página, zoom, anclas](reading-positions.md) y [búsquedas recientes](search.md) en tus otros Mac. |
| Storage | Muestra cuánto espacio ocupan los datos de VectorPDF y [los borra](#free-up-space-or-remove-data). |
| Automatically check for updates | Busca una nueva versión en GitHub aproximadamente una vez al día. Haz clic en Check Now para buscar en cualquier momento. |

## Liberar espacio o eliminar datos {#free-up-space-or-remove-data}

En Storage, los ajustes muestran cuánto espacio ocupa cada tipo de datos:

- **Índices del Agent:** lo que el Agent crea para responder preguntas sobre un documento. Haz clic en Clear para eliminarlos; el documento se vuelve a indexar la próxima vez que uses el Agent con él. VectorPDF los mantiene por debajo de 500 MB, eliminando primero los que llevan más tiempo sin usarse, y elimina el índice de un documento cuando el documento ya no existe.
- **Historial de lectura:** la última página, el zoom, las anclas y las búsquedas recientes de cada documento. Haz clic en Clear para olvidarlos, en este Mac y en iCloud.
- **Archivos temporales:** copias creadas al editar, guardar, imprimir o exportar, y actualizaciones descargadas. VectorPDF elimina las que hayan quedado la próxima vez que se abre.

Para eliminar todo lo que VectorPDF ha guardado, haz clic en Remove All VectorPDF Data. Esto también elimina tus ajustes, favoritos, grupos de pestañas, sello y claves de API, y luego cierra VectorPDF. Tus documentos no se modifican. Antes, guarda o cierra los documentos con cambios sin guardar.

## Actualizar VectorPDF

Elige VectorPDF > Check for Updates. Si hay una nueva versión, haz clic en Download. Cuando termine la descarga, haz clic en **Quit and Open Installer** y arrastra VectorPDF a la carpeta Aplicaciones.

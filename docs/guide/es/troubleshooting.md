<!-- keywords: damaged, corrupt, unreadable, solución de problemas, problema, problemas, no funciona, ayuda, solucionar, soporte, troubleshooting, problem, problems, not working, help, fix, support -->
<!-- source: 0ca329d057c7 -->

# Solución de problemas

## No puedo seleccionar texto, seguir enlaces ni usar las herramientas de anotación

Comprueba que no haya ninguna herramienta de Markup o Measurement activa. Pulsa Escape, o vuelve a hacer clic en la herramienta seleccionada, para volver a seleccionar texto.

## Una búsqueda no encuentra nada

- Puede que las páginas estén escaneadas. Consulta [Buscar y seleccionar texto en páginas escaneadas](scanned-pages.md).
- Comprueba que Match Case y Whole Word estén desactivadas en las [opciones de búsqueda](search.md#search-options), y que Smart Search esté activada.
- Si hay marcas que interrumpen el texto, añade un [patrón ignorado](search.md#ignore-clutter-in-the-text).

## Mantener pulsada la tecla ⌘ no muestra una previsualización

Link Peek funciona con los enlaces del documento y con los enlaces web a documentos abiertos en otra pestaña. Las referencias de texto simple no son enlaces, así que haz clic en ellas con el botón derecho. Consulta [Referencias entre documentos](cross-document-references.md).

Además, la ventana de VectorPDF debe ser la ventana activa.

## No se encuentra una referencia a otro documento

Abre el otro documento como pestaña en la misma ventana. No se busca en ventanas separadas.

## Un documento aparece como dañado

Si VectorPDF no encuentra ninguna página en un archivo, indica que no se ha podido abrir. Es posible que el archivo esté dañado o incompleto, o que use funciones que VectorPDF no puede leer. Prueba a descargarlo de nuevo o a abrirlo en otra app de PDF.

## Un documento en la nube no se abre

Comprueba tu conexión y que el archivo se descargue en el Finder, y vuelve a intentarlo.

## El Agent no está disponible o solo muestra pasajes

El Agent requiere macOS 26 o posterior, y para redactar respuestas en el dispositivo, Apple Intelligence debe estar activado y listo. Si falla la indexación, haz clic en Retry en la pestaña Ask About This Document. Consulta [Elegir cómo responde el Agent](agent-engines.md).

## Un modelo en línea no responde

Comprueba la clave de API y el modelo en [Settings](settings.md), y que tu cuenta en el servicio tenga saldo. VectorPDF responde en el dispositivo si el servicio falla.

## Mis cambios han desaparecido

Los cambios deben [guardarse](save.md). Si otra app cambió el archivo mientras tenías cambios sin guardar, al elegir Reload from Disk se descartan.

## La ayuda no muestra esta guía

Tips solo puede mostrar esta guía cuando VectorPDF está en la carpeta Aplicaciones. Muévelo allí y vuelve a elegir Help > VectorPDF Help.

## Obtener más ayuda

Informa de un problema o haz una pregunta en [GitHub](https://github.com/tomderham/vectorpdf/issues). Si puedes compartir un PDF de muestra, será de ayuda.

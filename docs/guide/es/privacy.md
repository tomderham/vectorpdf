<!-- keywords: privacidad, datos, red, telemetría, analíticas, seguridad, privacy, data, network, telemetry, analytics, iCloud, security -->
<!-- source: 4fdc452a0a96 -->

# Privacidad

VectorPDF no tiene cuentas, analíticas, telemetría ni informes de fallos. Tus documentos se procesan en tu Mac y no se envía nada de ellos al desarrollador.

## Qué usa la red

- **Búsqueda de actualizaciones:** VectorPDF consulta a GitHub la última versión aproximadamente una vez al día, o cuando eliges Check for Updates. La solicitud no contiene información sobre ti ni sobre tus documentos. Puedes desactivarla en [Settings](settings.md).
- **El Agent:** con el motor On-Device, nada sale de tu Mac. [Private Cloud Compute y los modelos en línea](agent-engines.md) envían tu pregunta y pasajes del documento, y solo cuando haces una pregunta. Al configurar un modelo en línea, también se usa tu clave para obtener la lista de sus modelos y enviar una prueba breve.
- **iCloud:** tu estado de lectura se guarda en tu propia cuenta de iCloud: dónde está el archivo, la última página y el zoom, y los nombres, extractos y páginas de tus anclas. Los documentos, su texto completo y las miniaturas de las anclas no se cargan.
- **Los enlaces en los que haces clic** se abren en el navegador.
- **Servicios de Apple:** macOS proporciona Translation, Look Up, la voz y el OCR, que pueden descargar archivos de idioma de Apple. Handoff comparte el documento y la página que estás leyendo con tus otros dispositivos.

## Qué se guarda en tu Mac

VectorPDF guarda tus preferencias, favoritos, grupos de pestañas, posiciones de lectura, anclas y sello. También conserva un índice de los documentos que has usado con el Agent, miniaturas de las anclas y copias de trabajo temporales de los documentos con ediciones de páginas o censuras sin guardar, que elimina cuando ya no las necesita.

Las claves de API de los modelos en línea se guardan en tu llavero de inicio de sesión.

Para ver todos los detalles, consulta la [política de privacidad en GitHub](https://github.com/tomderham/vectorpdf/blob/main/PRIVACY.md).

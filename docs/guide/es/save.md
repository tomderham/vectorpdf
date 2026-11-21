<!-- keywords: guardar, guardar como, sin guardar, compartir, mostrar en el Finder, cambios, revertir, última versión guardada, volver a cargar, descartar, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all, guardado automático, recuperar, recuperación, fallo, cierre inesperado, autosave, recover, recovery, crash, quit unexpectedly -->
<!-- source: 9cd8a419ddbd -->

# Guardar los cambios

Las anotaciones, los datos de formularios, los cambios de páginas y las censuras no se escriben en el archivo hasta que lo guardas. Una ventana con cambios sin guardar muestra un punto en su botón de cierre.

| Para | Haz esto |
| --- | --- |
| Guardar | Elige File > Save o pulsa ⌘S |
| Guardar una copia con otro nombre | Elige File > Save As o pulsa ⇧⌘S |
| Guardar una copia protegida con contraseña | Elige File > [Save Encrypted with Password](passwords.md) o pulsa ⌥⌘S |

Si cierras un documento con cambios sin guardar, VectorPDF te pregunta si quieres guardarlos.

Un documento [firmado digitalmente](digital-signatures.md) se guarda añadiendo tus cambios después de lo firmado, para que sus firmas sigan siendo válidas en la medida en que los cambios estén permitidos.

## Descartar los cambios

Para descartar todo lo que hayas hecho desde la última vez que guardaste, elige File > Revert to Saved. VectorPDF te lo pregunta primero y, a continuación, abre el archivo tal como se guardó por última vez, en la página que estabas leyendo. No se puede deshacer.

Para crear una copia más pequeña de un documento, consulta [Optimized PDF](export.md#optimized-pdf).

## Si VectorPDF se cierra de forma inesperada {#if-vectorpdf-quits-unexpectedly}

Mientras un documento tiene cambios sin guardar, VectorPDF conserva una copia en tu Mac, que actualiza cada 30 segundos aproximadamente. Si VectorPDF se cierra de forma inesperada, ofrece las copias la próxima vez que se abre:

- **Open Recovered Copy** guarda cada copia junto a su original, con el nombre «(Recovered)», y la abre. El original no cambia. Compáralos y quédate con el que quieras.
- **Decide Later** conserva las copias y vuelve a preguntar la próxima vez.
- **Discard Changes** elimina las copias.

La copia se elimina cuando guardas el documento, lo restauras o lo cierras sin guardar, y cuando sales de VectorPDF. Los documentos protegidos con contraseña no se copian, porque la copia no estaría cifrada. Tampoco se copian los documentos firmados digitalmente: cada vez que se guarda un documento firmado, queda en el archivo como una revisión, así que los cambios que hicieras y luego quitaras antes de guardar permanecerían en él. Guarda tú mismo un documento firmado mientras trabajas.

## Compartir un documento

Elige File > Share para usar un servicio para compartir de macOS, o File > Show in Finder (⇧⌘R) para encontrar el archivo. En la pantalla de inicio, haz clic con el botón derecho en un documento para mostrarlo en el Finder.

## Qué no se guarda en el PDF

Algunas cosas se quedan en VectorPDF y no acompañan al archivo: las [anclas](anchors.md), tu [posición de lectura](reading-positions.md), la rotación de la vista y el texto del [OCR](scanned-pages.md), a menos que lo [guardes en el PDF](scanned-pages.md#save-the-recognized-text-in-the-pdf).

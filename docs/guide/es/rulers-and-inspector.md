<!-- keywords: barra de estado, posición del puntero, coordenadas, tamaño de página, tamaño de papel, reglas, guías, cuadrícula, ajustar, unidades, milímetros, pulgadas, puntos, Inspector, tipo de letra, tamaño de letra, color, resolución de imagen, navegador, recuento de palabras, recuento de caracteres, status bar, pointer position, coordinates, page size, paper size, A4, Letter, ARCH, rulers, guides, grid, snap, units, millimeters, inches, points, font, font size, image resolution, dpi, ppi, line width, navigator, pan and zoom, word count, character count -->
<!-- source: f1f2dd215a95 -->

# Reglas, barra de estado e Inspector

Muestran dónde están las cosas en una página y de qué están hechas. Están desactivadas hasta que las activas en el menú View, para que la lectura siga despejada.

## La barra de estado

Elige View > Show Status Bar (⌘/) para mostrar una franja bajo la página. Muestra:

- **Dónde está el puntero** en la página, desde la esquina superior izquierda de la página. En una página con [escala de dibujo](drawing-scale.md), también muestra ese lugar en unidades reales.
- **El tamaño de la página** bajo el puntero, o de la página actual, con el tamaño de papel cuando coincide con uno: A0 a A6, B3 a B5, Letter, Legal, Tabloid, ANSI C a E y ARCH A a E. Los juegos de planos suelen mezclar tamaños de hoja, así que cambia al pasar de una página a otra.
- **Una medición mientras la dibujas:** su longitud, su ángulo y cuánto avanza en horizontal (ΔX) y en vertical (ΔY); la longitud de un perímetro hasta el momento y su último segmento; un área hasta el momento y su perímetro. Consulta [Medir longitudes, áreas y ángulos](measure.md).
- **El tamaño de la selección de texto,** en palabras y caracteres.

Elige las unidades, Millimeters, Inches o Points, en el menú de la derecha de la barra de estado. Las reglas, la cuadrícula y el Inspector también las usan.

## Reglas y guías

Elige View > Rulers and Grid > Show Rulers (⌘R) para mostrar reglas en la parte superior e izquierda de la página. Miden la página bajo el puntero desde su esquina superior izquierda, y una línea en cada regla muestra dónde está el puntero.

| Para | Haz esto |
| --- | --- |
| Añadir una guía | Arrastra desde una regla hasta la página |
| Mover una guía | Arrástrala |
| Quitar una guía | Arrástrala fuera de la página |
| Quitar todas las guías | Elige View > Rulers and Grid > Clear Guides |

Las guías pertenecen a la página en la que las pones. Se mantienen mientras el documento está abierto y no se guardan en él.

## La cuadrícula

Elige View > Rulers and Grid > Show Grid (⌘') para dibujar una cuadrícula en cada página, desde su esquina superior izquierda. Elige su separación en View > Rulers and Grid > Grid Spacing. Una de cada cinco líneas es más oscura.

Cuando **Snap to Guides and Grid** está activado en View > Rulers and Grid, los puntos de una medición se ajustan a las guías cercanas al puntero, y a la cuadrícula mientras se muestra, igual que se ajustan a las esquinas con Vertex Magnetic Snapping.

## El Inspector {#the-inspector}

Elige View > Show Inspector (⌃⌘I) para mostrar el Inspector junto a la página. También puedes hacer clic con el botón derecho en la página y elegir Inspect. Si has [movido la búsqueda a la derecha](search.md#see-results-beside-the-outline), los dos comparten ese lado: cambia de uno a otro con los botones Search e Inspector de la parte superior.

- **Texto, imágenes y dibujos:** con el Inspector abierto, haz clic en la página en el modo Select. El Inspector muestra lo que hay dibujado allí, y la página lo resalta:
  - **Texto:** el tipo de letra, su tamaño, el carácter, su color y espacio de color, y si el tipo de letra está en el archivo. Uno que no lo está se dibuja con un sustituto, que puede verse distinto al imprimir.
  - **Imágenes:** su tamaño en píxeles, su resolución tal como están colocadas en la página, su tamaño en la página, su espacio de color y los bits por componente. Comprueba la resolución de una imagen antes de imprimir u optimizar.
  - **Dibujos:** el grosor y el color de una línea, o el color de relleno de una forma.
- **Anotaciones:** selecciona una anotación para ver su tipo, autor, fechas, capa, opacidad y color. Para moverla, escribe su posición (**X** e **Y**, desde la esquina superior izquierda de la página) y pulsa Retorno. Los rectángulos, óvalos, cuadros de texto, globos, sellos y nubes de revisión también se pueden redimensionar: escribe su **Width** y su **Height**.

## El navegador

Elige View > Show Navigator (⌃⌘N) para mostrar una miniatura de la página visible en la esquina de la ventana. La parte que está en pantalla aparece recuadrada. Arrastra el recuadro, o haz clic en la miniatura, para moverte por una hoja grande con mucho zoom.

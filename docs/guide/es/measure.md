<!-- keywords: rectángulo, círculo, radio, diámetro, arco, longitud de arco, medir, medición, mediciones, medida, medidas, longitud, distancia, cota, dimensión, perímetro, área, ángulo, orto, ajuste, measure, measurement, measurements, length, distance, dimension, perimeter, area, angle, ortho, snap, snapping, editar, cambiar, mover, tirador, desplazamiento, edit, change, move, reshape, handle, offset, contar, recuento, conteo, símbolos, count, counting, tally, symbols, rectangle, circle, radius, diameter, arc, arc length, curve -->
<!-- source: fea799877718 -->

# Medir longitudes, áreas y ángulos, y contar

Pulsa ⇧⌘M para mostrar la barra de herramientas Measurement. Si tu plano está a escala, [define la escala](drawing-scale.md) primero.

Amplía la vista antes de medir para ganar precisión. Al pulsar Escape se cancela una medición en curso. Pulsa Escape otra vez, o haz clic en la herramienta seleccionada, para dejar la herramienta.

## Herramientas de medición

| Herramienta | Cómo se usa |
| --- | --- |
| Linear Dimension | Arrastra de un punto al otro. |
| Perimeter | Haz clic en cada punto del recorrido. Pulsa Return o haz doble clic para terminar. |
| Polygon Area | Haz clic en cada esquina. Pulsa Return, haz doble clic o haz clic en el primer punto para cerrar la forma. |
| Rectangle Area | Arrastra de una esquina a la opuesta. |
| Circle | Arrastra del centro al borde. La etiqueta muestra el área y el diámetro, y la [barra de estado](rulers-and-inspector.md) muestra también el radio y la circunferencia. |
| Arc Length | Haz clic donde empieza el arco, en un punto del arco y donde termina. La etiqueta muestra la longitud a lo largo del arco y su radio. |
| Vertex Angle | Haz clic en un punto de la primera línea, luego en la esquina y después en un punto de la segunda línea. |
| Count | Escribe lo que cuentas en el cuadro de grupo, como Enchufes, y haz clic en cada uno. |

## Contar elementos en un plano {#count-things-on-a-drawing}

Elige la herramienta Count y escribe un nombre de grupo en el cuadro de al lado, como Enchufes o Puertas tipo A, o elige uno que ya exista en el documento en el menú junto al cuadro. Cada clic coloca un marcador, un punto del color de la barra Measurement, y la barra muestra cuántos de ese grupo hay en la página. Cambia el nombre del grupo para contar otra cosa; cada grupo se cuenta por separado. Usa un color distinto para cada grupo para distinguirlos en la página.

Para mover un marcador, arrástralo con la herramienta Select. Para quitar uno, haz clic con el botón derecho en él y elige Delete Count Marker. La [tabla de mediciones](takeoff.md) muestra cuántos de cada grupo hay en cada página, con totales. Los marcadores se guardan en el PDF como pequeños círculos, así que otras apps también los muestran.

## Dibujar con precisión

- **Ortho Lock** mantiene las líneas a 0°, 45° y 90°. Mantén pulsada la tecla ⇧ para invertirlo en una sola línea: para medir con cualquier ángulo mientras está activado, o para mantener una línea recta mientras está desactivado.
- **Vertex Magnetic Snapping** ajusta el puntero a las esquinas y los extremos del plano.
- **Guías y cuadrícula:** con View > Rulers and Grid > Snap to Guides and Grid activado, los puntos se ajustan a las guías que hayas arrastrado desde las reglas y a la cuadrícula mientras se muestra. Consulta [Reglas, barra de estado e Inspector](rulers-and-inspector.md).
- **La barra de estado** (View > Show Status Bar) muestra más de una medición mientras la dibujas que su etiqueta: su ángulo y cuánto avanza en horizontal y en vertical, o el perímetro de un área hasta el momento.

## Cambiar una medición

Elige **Select**, la flecha al principio de la barra Measurement, o pulsa Escape para dejar la herramienta de medición. Apunta a una medición y un contorno discontinuo la muestra; haz clic en ella para seleccionarla. Haz clic con ⇧ pulsada para seleccionar varias, o mantén pulsada ⌥ y arrastra sobre ellas. Con una herramienta de medición en uso, un clic vuelve a medir.

Una medición seleccionada tiene tiradores en sus puntos.

| Para | Haz esto |
| --- | --- |
| Mover un punto | Arrastra su tirador. Ortho Lock y el ajuste funcionan igual que al medir. |
| Mover toda la medición | Arrastra su línea o pulsa las teclas de flecha (con ⇧ se mueve 10 puntos). |
| Acercar o alejar una línea de cota de lo que mide | Arrastra su etiqueta o, cuando ya esté separada de los puntos, la propia línea de cota. |
| Cambiar su color | Elige un color con el botón de color de la barra de herramientas Measurement. |
| Cambiar su grosor de línea | Elige o escribe un grosor en el cuadro de grosor de línea de la barra Measurement. |

El valor se vuelve a calcular mientras arrastras. Arrastra más allá del borde de la ventana para desplazarte, si la medición es más larga que la vista. Elige Edit > Undo para devolver una medición a como estaba. También se pueden cambiar las mediciones ya guardadas en el PDF.

Para seleccionar un área, haz clic en su borde: al hacer clic dentro se selecciona el texto que hay ahí.

Un rectángulo, círculo o arco conserva su forma al cambiarlo: arrastra una esquina del rectángulo, el centro o el borde del círculo, o cualquiera de los tres puntos del arco. Se guardan como un área o una longitud a lo largo de su contorno, así que otras apps que leen mediciones PDF también los muestran como mediciones, con sus propias cifras para el contorno (a menos del 0,05 % de las de VectorPDF en un círculo o un arco).

## Cambiar el aspecto de las mediciones

Usa el botón de color y el cuadro de grosor de línea de la barra de herramientas Measurement antes de medir. Elige un grosor en puntos o escribe uno, de 0,1 a 72 puntos. Las mediciones nuevas son grises, de 1,5 puntos, hasta que elijas otra cosa. VectorPDF recuerda lo que eliges, y la barra Markup conserva sus propios colores y grosores. Para cambiar el color o el grosor de una medición que ya has hecho, selecciónala y elige un color o grosor en la barra Measurement. El grosor se guarda en el PDF.

## Conservar o eliminar mediciones

Las mediciones son anotaciones que se guardan en el PDF cuando lo [guardas](save.md). Para eliminar una, haz clic con el botón derecho en ella y elige el comando de eliminar, como Delete Dimension, Delete Area Takeoff, Delete Circle Measurement o Delete Count Marker.

Para ver una lista de todas tus mediciones, consulta la [tabla de mediciones](takeoff.md).

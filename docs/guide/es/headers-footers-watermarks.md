<!-- keywords: logotipo, marca de agua con imagen, varios archivos, chino, hindi, árabe, encabezado, encabezados, pie de página, pies de página, números de página, numeración de páginas, Bates, números Bates, numeración Bates, marca de agua, marcas de agua, BORRADOR, CONFIDENCIAL, legal, header, headers, footer, footers, page numbers, page numbering, Bates numbers, Bates numbering, watermark, watermarks, DRAFT, CONFIDENTIAL, stamp text, discovery, PDF, Chinese, Japanese, Korean, Hindi, Arabic, any language, logo, picture watermark, image watermark -->
<!-- source: 05436b7b8113 -->

# Encabezados, pies de página, números Bates y marcas de agua

Puedes poner texto en la parte superior e inferior de las páginas, como un título, números de página o números Bates, y una marca de agua como BORRADOR o CONFIDENCIAL atravesándolas. Elige Edit > Headers, Footers and Watermark, rellena las partes que quieras y haz clic en **Add**. Una vista previa junto a los ajustes muestra la página que estás leyendo tal como quedará, con sus propios números de página y Bates; usa las flechas de debajo para ver otras páginas.

VectorPDF guarda en el documento lo que elegiste, así que más adelante puedes cambiar los encabezados, los pies de página y la marca de agua, o quitarlos. Vuelve a elegir Edit > Headers, Footers and Watermark, haz los cambios y haz clic en **Update**. Para quitarlos todos, haz clic en **Remove All**.

Los cambios pasan a formar parte del archivo cuando lo [guardas](save.md).

## Encabezado y pie de página

Escribe en cualquiera de las seis casillas: la izquierda, el centro y la derecha del encabezado y del pie de página. Deja una casilla vacía para no poner nada en ella.

Para añadir un número de página u otro valor que cambia de una página a otra, haz clic en una casilla y elige en el menú **Insert**:

| Insert | Muestra |
| --- | --- |
| Page Number | El número de la página, contando desde la primera página marcada. Consulta [Páginas y números](#pages-and-numbers). |
| Page Count | Cuántas páginas tiene el documento |
| Bates Number | El número Bates de la página |
| Date | La fecha de hoy |
| File Name | El nombre de archivo del documento |

Cada uno aparece en la casilla como una palabra entre comillas angulares dobles, como `<<page>>`. Por ejemplo, escribe `Página `, inserta Page Number, escribe ` de ` e inserta Page Count para obtener “Página 3 de 12”.

Puedes elegir el tipo de letra, el tamaño y el color del texto, y los márgenes: a qué distancia está el encabezado de la parte superior de la página, el pie de la parte inferior, y ambos de los lados, en puntos (72 puntos son una pulgada).

El texto puede estar en cualquier idioma, como chino, hindi o árabe. Si el tipo de letra elegido no tiene sus caracteres, se usa uno de tu Mac que sí los tenga, y los caracteres usados se guardan en el documento para que se vea igual en todas partes.

## Marca de agua

Una marca de agua es un texto o una imagen. Para texto, escríbelo; pulsa Retorno para una segunda línea. Para una imagen, como un logotipo, elige **Picture**, haz clic en **Choose Picture** y ajusta su anchura como proporción de la de la página. Después elige:

- **Font** y **Color**.
- **As large as fits the page**, o un tamaño propio.
- **Opacity:** con qué intensidad se ve. Una marca de agua clara deja la página legible.
- **Angle:** horizontal, diagonal o vertical.
- **Behind the page's content:** dibuja la marca de agua bajo el texto y las imágenes de la página en lugar de encima. Una página con fondo, como una página escaneada, oculta una marca de agua que esté detrás.

## Páginas y números {#pages-and-numbers}

- **Pages:** todas las páginas, las páginas impares o pares, y de una página a otra. Deja From o To vacío para la primera o la última página.
- **First page marked is page:** el número que Page Number da a la primera página marcada. Los números aumentan en uno por cada página marcada.
- **Bates numbers:** un prefijo, como el nombre de un caso o de una empresa, el número de cifras, el número por el que empezar y un sufijo. Los números Bates aumentan en uno por cada página marcada y se rellenan con ceros, como ACME-000001. Inserta Bates Number en un encabezado o pie de página para mostrarlos.

## Marcar varios archivos

Para numerar un conjunto de documentos, por ejemplo para un procedimiento judicial, con números Bates que continúan de un archivo al siguiente, configura las marcas y haz clic en **Apply to Other Files**. Elige los PDF y después una carpeta para las copias marcadas; los archivos en sí no se modifican. Se marcan por orden de nombre, así que nómbralos en el orden en que deben numerarse. Al terminar, VectorPDF indica qué números Bates se usaron y enumera los archivos que no pudo marcar, como uno que necesite contraseña.

## Conviene saber

- Los encabezados, los pies de página y las marcas de agua forman parte de la página, no son [anotaciones](draw-and-notes.md), así que se imprimen y se ven en otras apps. Están marcados como decoración de página, que los lectores de pantalla pueden omitir. Puedes buscar y seleccionar su texto.
- Los márgenes se miden en la página tal como se muestra, así que en una página girada el encabezado sigue arriba.
- Los encabezados, pies de página y marcas de agua que añadieron otras apps, como Adobe Acrobat, también se pueden quitar si la app los marcó como tales (la mayoría lo hace): cuando VectorPDF encuentra alguno, aparece **Remove them** en Pages & Numbers, y la vista previa muestra la página sin ellos. Una vez quitados, solo vuelven si recuperas la versión guardada del documento.
- Añadirlos a un documento [firmado digitalmente](digital-signatures.md) cambia lo que se firmó, así que sus firmas dejan de ser válidas.

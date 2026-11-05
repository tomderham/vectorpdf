<!-- keywords: capas, capa, contenido opcional, CAD, planos, dibujos, mostrar, ocultar, visibilidad, marcados, anotaciones, nueva capa, cambiar nombre de capa, eliminar capa, layers, layer, optional content, OCG, AutoCAD, Revit, show, hide, visibility, markups, annotations, new layer, rename layer, delete layer -->
<!-- source: 0a0a671f9044 -->

# Mostrar y ocultar capas

Los planos exportados desde programas de CAD y diseño suelen tener cada parte de una hoja en su propia capa: muros, electricidad, fontanería, cotas, nubes de revisión. Puedes mostrar u ocultar cada una.

La pestaña Layers aparece en la parte superior de la barra lateral solo cuando el documento tiene capas. Para dar a un documento su primera capa, consulta [Añadir, renombrar y eliminar capas](#add-rename-and-delete-layers).

- **Mostrar u ocultar una capa:** haz clic en su casilla. La página se vuelve a dibujar al instante.
- **Elegir una de un grupo:** algunos documentos agrupan capas para que solo se muestre una a la vez, como los idiomas o las escalas de una hoja. Estas tienen botones redondos; al elegir una se ocultan las demás.
- **Encabezados:** agrupan las capas que aparecen debajo y no se pueden ocultar.
- **Capas bloqueadas:** tienen un candado al lado. El documento no permite mostrarlas ni ocultarlas.

Las capas que ocultas también se omiten al [imprimir](print.md), [seleccionar texto](select-text.md) o [buscar](search.md), así que solo trabajas con lo que ves.

## Poner anotaciones en una capa

Las anotaciones también pueden ir en una capa, de modo que se muestran y ocultan con ella. Otras apps que leen capas, como Acrobat y Bluebeam, las muestran y ocultan del mismo modo.

- **Elegir dónde van las anotaciones nuevas:** en la [barra de herramientas Markup](draw-and-notes.md) o la [barra de herramientas Measurement](measure.md), haz clic en el menú de capas (indica **No Layer** hasta que elijas una) y elige una capa. Todo lo que crees a partir de entonces irá en ella, hasta que elijas otra capa o **No Layer**. También puedes hacer clic con el botón derecho en una capa de la pestaña Layers y elegir **Put New Annotations Here**. La capa donde van las anotaciones nuevas tiene un lápiz al lado.
- **Mover una anotación a otra capa:** haz clic en ella con el botón derecho y elige **Layer** y luego una capa, o **None** para quitarla de cualquier capa.
- **Añadir una capa propia:** consulta [Añadir, renombrar y eliminar capas](#add-rename-and-delete-layers).

El menú de capas solo aparece cuando un documento tiene capas, así que las barras de herramientas de los demás documentos no cambian.

Las anotaciones de una capa oculta desaparecen de la página, de la [pestaña Comments](draw-and-notes.md#see-all-annotations) y de la [tabla de cubicación](takeoff.md), y no se pueden seleccionar ni borrar. La tabla Annotations las sigue mostrando, con su capa.

Si eliges una capa oculta para las anotaciones nuevas, se muestra, para que lo que crees no desaparezca. Undo devuelve una anotación a la capa en la que estaba.

## Añadir, renombrar y eliminar capas {#add-rename-and-delete-layers}

Los revisores suelen poner sus marcados en capas propias, como una por oficio o por ronda de revisión, incluso en planos que llegaron sin capas. Cada uno de estos comandos cambia el documento, y Undo lo revierte.

- **Añadir una capa:** elige Edit > New Layer… y ponle un nombre. Funciona en cualquier PDF, así que es como un documento obtiene su primera capa; después aparecen la pestaña Layers y los menús de capas. Las anotaciones nuevas van en la capa nueva. En un documento que ya tiene capas, también puedes hacer clic en **+** en la parte superior de la pestaña Layers, o elegir **New Layer…** en el menú de capas.
- **Renombrar una capa:** elige Edit > Rename Layer…, elige la capa y escribe su nuevo nombre.
- **Eliminar una capa:** elige Edit > Delete Layer… y luego la capa. Sus anotaciones se quedan en la página, sin capa. Solo se pueden eliminar las capas que contienen únicamente anotaciones: eliminar una en la que está el propio plano dejaría esa parte del plano siempre visible, así que esas no aparecen en la lista.

## Qué se guarda

Las capas que añades, renombras o eliminas se guardan con el documento, igual que las capas en las que están las anotaciones.

Qué capas se muestran no se guarda con el documento. La próxima vez que lo abras, sus capas se mostrarán como lo indique el propio documento, y cualquier persona a la que se lo envíes verá lo mismo.

> **Nota:** Un documento de una o dos páginas con capas se abre en la pestaña Layers, salvo que hayas ocultado la barra lateral para él. Usa el botón de la barra lateral en la barra de herramientas para mostrarla.

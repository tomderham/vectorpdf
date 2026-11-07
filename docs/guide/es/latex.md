<!-- keywords: LaTeX, TeX, SyncTeX, búsqueda directa, búsqueda inversa, código fuente, fuente, editor, saltar al código, LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->
<!-- source: a865c846e0d7 -->

# Ir entre el código LaTeX y el PDF

Si escribes en LaTeX, VectorPDF puede llevarte de un lugar del PDF a la línea de código que lo generó, y de una línea de código al lugar que generó en el PDF. Para ello usa SyncTeX, que TeX activa cuando compila con `-synctex=1`. La mayoría de los editores de LaTeX compilan así.

SyncTeX funciona con un PDF que tiene al lado su archivo SyncTeX, con el mismo nombre que el PDF: `paper.pdf` y `paper.synctex.gz`. Los demás PDF de la carpeta no se ven afectados.

## Elegir tu editor

1. Elige VectorPDF > Settings y haz clic en Set Up… junto a LaTeX (SyncTeX).
2. Elige tu editor en Source Editor: Visual Studio Code, VSCodium, Cursor, Zed, Sublime Text, BBEdit, TextMate, MacVim, Emacs o TeXstudio.
3. Si tu editor no aparece, elige Other e introduce el comando que abre un archivo en una línea. Escribe `%file` para el archivo y `%line` para la línea, por ejemplo `myeditor +%line %file`.

Debajo del editor, Settings muestra el programa que ha encontrado. Si indica que no lo ha encontrado, instala la herramienta de línea de comandos de tu editor, o elige Other e indica la ruta completa del programa.

## Ir del PDF al código

Haz clic con ⇧⌘ en un lugar del PDF. Tu editor abre el archivo de código en la línea que lo generó.

También puedes hacer clic con el botón derecho y elegir **Show in Editor**. Está al principio del menú de un PDF con archivo SyncTeX.

## Ir del código al PDF

Tu editor pide a VectorPDF que muestre una línea ejecutando `displayline`, que viene con VectorPDF:

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

VectorPDF pasa el PDF al frente, lo abre si no está abierto y resalta la línea en rojo durante un momento. Solo se desplaza si la línea no está ya en pantalla. Añade `-g` antes de LINE para dejar VectorPDF detrás de tu editor.

`displayline` acepta los mismos argumentos que el de Skim. Si tu editor tiene un ajuste para Skim, usa en su lugar el `displayline` de VectorPDF.

### Visual Studio Code

Con la extensión LaTeX Workshop, añade estas líneas a tus ajustes. Para encontrarlos, elige Preferences: Open User Settings (JSON) en la paleta de comandos.

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

Después, en Visual Studio Code, pulsa ⌥⌘B para compilar, ⌥⌘V para abrir el PDF en VectorPDF y ⌥⌘J para mostrar la línea en la que estás. Con el último ajuste, VectorPDF también muestra esa línea después de cada compilación.

## Mientras escribes

Cuando tu editor vuelve a compilar el PDF, VectorPDF lo vuelve a cargar y conserva tu posición, el zoom, la rotación y la disposición de páginas. Si el archivo aún se está escribiendo, VectorPDF espera a que termine.

## Si no funciona

- **Show in Editor no aparece en el menú:** el PDF no tiene archivo SyncTeX. Compila con SyncTeX activado y deja el archivo SyncTeX junto al PDF, o en una carpeta llamada build u out junto a él.
- **No Source Here:** no hay ninguna línea de código para ese lugar, como un margen o una imagen. Haz clic en el texto.
- **No pasa nada en VectorPDF:** comprueba que tu editor ejecuta el `displayline` de VectorPDF y que el PDF se ha compilado con SyncTeX activado desde la última vez que cambiaste el código.
- **Tu editor no encuentra TeX después de instalarlo:** sal del editor y vuelve a abrirlo.

<!-- keywords: LaTeX, TeX, SyncTeX, busca direta, busca inversa, código-fonte, fonte, editor, ir para o código, LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->
<!-- source: a865c846e0d7 -->

# Ir entre o código LaTeX e o PDF

Se você escreve em LaTeX, o VectorPDF pode levar você de um ponto do PDF à linha do código que o gerou, e de uma linha do código ao ponto que ela gerou no PDF. Para isso ele usa o SyncTeX, que o TeX ativa quando compila com `-synctex=1`. A maioria dos editores de LaTeX compila assim.

O SyncTeX funciona com um PDF que tem ao lado o seu arquivo SyncTeX, com o mesmo nome do PDF: `paper.pdf` e `paper.synctex.gz`. Os outros PDFs da pasta não são afetados.

## Escolher o editor

1. Escolha VectorPDF > Settings e clique em Set Up… ao lado de LaTeX (SyncTeX).
2. Escolha seu editor em Source Editor: Visual Studio Code, VSCodium, Cursor, Zed, Sublime Text, BBEdit, TextMate, MacVim, Emacs ou TeXstudio.
3. Se o seu editor não estiver na lista, escolha Other e digite o comando que abre um arquivo em uma linha. Escreva `%file` para o arquivo e `%line` para a linha, por exemplo `myeditor +%line %file`.

Abaixo do editor, Settings mostra o programa encontrado. Se disser que o programa não foi encontrado, instale a ferramenta de linha de comando do seu editor, ou escolha Other e informe o caminho completo do programa.

## Do PDF para o código

Clique em um ponto do PDF com ⇧⌘ pressionadas. Seu editor abre o arquivo de código na linha que o gerou.

Você também pode clicar com o botão direito e escolher **Show in Editor**. O comando fica no topo do menu de um PDF com arquivo SyncTeX.

## Do código para o PDF

Seu editor pede ao VectorPDF que mostre uma linha executando o `displayline`, que vem com o VectorPDF:

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

O VectorPDF traz o PDF para a frente, abre-o se ele não estiver aberto e destaca a linha em vermelho por um momento. Ele só rola se a linha ainda não estiver na tela. Adicione `-g` antes de LINE para deixar o VectorPDF atrás do editor.

O `displayline` aceita os mesmos argumentos que o do Skim. Se o seu editor tiver um ajuste para o Skim, use o `displayline` do VectorPDF no lugar.

### Visual Studio Code

Com a extensão LaTeX Workshop, adicione estas linhas aos seus ajustes. Para encontrá-los, escolha Preferences: Open User Settings (JSON) na Paleta de Comandos.

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

Depois, no Visual Studio Code, pressione ⌥⌘B para compilar, ⌥⌘V para abrir o PDF no VectorPDF e ⌥⌘J para mostrar a linha em que você está. Com o último ajuste, o VectorPDF também mostra essa linha depois de cada compilação.

## Enquanto você escreve

Quando o editor compila o PDF de novo, o VectorPDF o recarrega e mantém sua posição, o zoom, a rotação e o layout das páginas. Se o arquivo ainda estiver sendo gravado, o VectorPDF espera até que termine.

## Se não funcionar

- **Show in Editor não aparece no menu:** o PDF não tem arquivo SyncTeX. Compile com o SyncTeX ativado e mantenha o arquivo SyncTeX ao lado do PDF, ou em uma pasta chamada build ou out ao lado dele.
- **No Source Here:** não há linha de código para esse ponto, como uma margem ou uma imagem. Clique no texto.
- **Nada acontece no VectorPDF:** verifique se o seu editor executa o `displayline` do VectorPDF e se o PDF foi compilado com o SyncTeX ativado desde a última alteração no código.
- **O editor não encontra o TeX depois da instalação:** encerre o editor e abra-o de novo.

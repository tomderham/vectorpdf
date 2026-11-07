<!-- keywords: exportar, converter, texto simples, texto, nivelar, resumo de anotações, planilha, otimizar, otimizado, reduzir tamanho, comprimir, menor, imagens, fontes, contornos, texto em contornos, plotter, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF, optimize, optimized, reduce file size, compress, smaller, downsample, images, fonts, subset, outlines, text to outlines, plotter -->
<!-- source: 6d68e3315dc3 -->

# Exportar para outros formatos

Para exportar um documento inteiro, escolha File > Export Document As e escolha Plain Text, Word Document, Scalable Vector Graphics, Flattened PDF ou Optimized PDF. O resumo de anotações e as medições têm comandos próprios.

## Plain Text

Salva o texto do documento em um arquivo `.txt`.

## Word Document

Salva um arquivo `.docx` que pode ser editado no Word e em outros apps. Layouts de página complexos podem ficar diferentes do PDF.

## SVG

Salva cada página como um arquivo Scalable Vector Graphics, com o texto em traçados vetoriais, para que fique exatamente igual ao PDF. Um documento de várias páginas é salvo como uma pasta com um arquivo por página.

## Flattened PDF {#flattened-pdf}

Salva um PDF em que as anotações e os campos de formulário passam a fazer parte da página, de modo que não possam ser alterados. Na caixa de diálogo de salvar, escolha o que deve ser nivelado:

- **Flatten annotations and markups**
- **Flatten form fields (make static)**

O PDF nivelado tem só o que está nas [camadas](layers.md) mostradas. As camadas ocultas ficam de fora, com tudo o que há nelas, inclusive anotações. As camadas que restam ainda podem ser mostradas e ocultadas, e as anotações niveladas na página continuam nas suas camadas.

> **Nota:** O nivelamento não remove o que está por baixo. Para remover conteúdo, use o [tarjamento](redact.md).

## Optimized PDF {#optimized-pdf}

Salva uma cópia menor do PDF, incluindo as alterações que você ainda não salvou. O documento aberto não é alterado. Os dados que o documento não usa mais são removidos, as duplicatas são combinadas e tudo é comprimido. Na caixa de diálogo de salvamento, você também pode escolher:

- **Keep only the characters each font uses:** remove as partes das fontes incorporadas que o documento não usa. Ativado por padrão.
- **Images:** mantenha as imagens como estão ou reduza-as para 300 dpi (para impressão) ou 150 dpi (para leitura na tela). Somente as imagens com resolução maior são reduzidas. As fotos são salvas como JPEG; diagramas e capturas de tela continuam sem perdas. Digitalizações em preto e branco não são alteradas.
- **Convert text to outlines:** desenha cada letra como uma forma, para que o documento tenha a mesma aparência em plotters, plotters de recorte e sistemas de impressão que não têm suas fontes. O texto da cópia não pode ser selecionado, pesquisado nem copiado.

O quanto a cópia fica menor depende do documento. Digitalizações e fotos são as que mais diminuem quando você reduz as imagens.

## Resumo de anotações

Escolha File > Export Annotations Summary (⇧⌘E) para salvar uma lista das anotações do documento, incluindo as de outros apps, com seus autores, status e respostas. Por padrão, é um arquivo Markdown. Dê ao arquivo a extensão `.csv` para salvar uma planilha.

## Medições

Para exportar medições, use a [tabela de levantamento](takeoff.md).

<!-- keywords: barra de status, posição do cursor, coordenadas, tamanho da página, tamanho do papel, réguas, guias, grade, encaixar, unidades, milímetros, polegadas, pontos, Inspector, fonte, tamanho da fonte, cor, resolução da imagem, navegador, contagem de palavras, contagem de caracteres, status bar, pointer position, coordinates, page size, paper size, A4, Letter, ARCH, rulers, guides, grid, snap, units, millimeters, inches, points, font, font size, color, image resolution, dpi, ppi, line width, navigator, pan and zoom, word count, character count -->
<!-- source: f1f2dd215a95 -->

# Réguas, barra de status e Inspector

Eles mostram onde as coisas estão em uma página e do que são feitas. Ficam desativados até você ativá-los no menu View, para que a leitura continue limpa.

## A barra de status

Escolha View > Show Status Bar (⌘/) para mostrar uma faixa abaixo da página. Ela mostra:

- **Onde o cursor está** na página, a partir do canto superior esquerdo da página. Em uma página com [escala de desenho](drawing-scale.md), também mostra esse lugar em unidades reais.
- **O tamanho da página** sob o cursor, ou da página atual, com o tamanho do papel quando corresponde a um: A0 a A6, B3 a B5, Letter, Legal, Tabloid, ANSI C a E e ARCH A a E. Conjuntos de desenhos costumam misturar tamanhos de folha, então isso muda conforme você passa de uma página a outra.
- **Uma medição enquanto você a desenha:** o comprimento, o ângulo e quanto ela avança na horizontal (ΔX) e na vertical (ΔY); o comprimento de um perímetro até o momento e seu último segmento; uma área até o momento e seu perímetro. Consulte [Medir comprimentos, áreas e ângulos](measure.md).
- **O tamanho da seleção de texto,** em palavras e caracteres.

Escolha as unidades, Millimeters, Inches ou Points, no menu à direita da barra de status. As réguas, a grade e o Inspector também as usam.

## Réguas e guias

Escolha View > Rulers and Grid > Show Rulers (⌘R) para mostrar réguas no topo e à esquerda da página. Elas medem a página sob o cursor a partir do canto superior esquerdo, e uma linha em cada régua mostra onde o cursor está.

| Para | Faça isto |
| --- | --- |
| Adicionar uma guia | Arraste de uma régua até a página |
| Mover uma guia | Arraste-a |
| Remover uma guia | Arraste-a para fora da página |
| Remover todas as guias | Escolha View > Rulers and Grid > Clear Guides |

As guias pertencem à página em que você as coloca. Elas permanecem enquanto o documento está aberto e não são salvas nele.

## A grade

Escolha View > Rulers and Grid > Show Grid (⌘') para desenhar uma grade em cada página, a partir do canto superior esquerdo. Escolha o espaçamento em View > Rulers and Grid > Grid Spacing. Uma em cada cinco linhas é mais escura.

Quando **Snap to Guides and Grid** está ativado em View > Rulers and Grid, os pontos de uma medição se encaixam nas guias perto do cursor, e na grade enquanto ela estiver visível, assim como se encaixam em cantos com Vertex Magnetic Snapping.

## O Inspector {#the-inspector}

Escolha View > Show Inspector (⌃⌘I) para mostrar o Inspector ao lado da página. Você também pode clicar com o botão direito na página e escolher Inspect. Se você [moveu a busca para a direita](search.md#see-results-beside-the-outline), os dois dividem esse lado: alterne entre eles com os botões Search e Inspector no topo.

- **Texto, imagens e desenhos:** com o Inspector aberto, clique na página no modo Select. O Inspector mostra o que está desenhado ali, e a página o destaca:
  - **Texto:** a fonte, o tamanho, o caractere, sua cor e espaço de cor, e se a fonte está no arquivo. Uma fonte que não está é desenhada com uma substituta, que pode ficar diferente na impressão.
  - **Imagens:** o tamanho em pixels, a resolução conforme posicionadas na página, o tamanho na página, o espaço de cor e os bits por componente. Verifique a resolução de uma imagem antes de imprimir ou otimizar.
  - **Desenhos:** a espessura e a cor de uma linha, ou a cor de preenchimento de uma forma.
- **Anotações:** selecione uma anotação para ver o tipo, o autor, as datas, a camada, a opacidade e a cor. Para movê-la, digite a posição (**X** e **Y**, a partir do canto superior esquerdo da página) e pressione Return. Retângulos, ovais, caixas de texto, balões, carimbos e nuvens de revisão também podem ser redimensionados: digite **Width** e **Height**.

## O navegador

Escolha View > Show Navigator (⌃⌘N) para mostrar, no canto da janela, uma miniatura da página visível. A parte que está na tela fica contornada. Arraste o contorno, ou clique na miniatura, para se mover por uma folha grande com zoom alto.

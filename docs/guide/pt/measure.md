<!-- keywords: medir, medida, medição, medições, comprimento, distância, dimensão, perímetro, área, ângulo, orto, encaixe, measure, measurement, measurements, length, distance, dimension, perimeter, area, angle, ortho, snap, snapping, editar, alterar, mover, alça, deslocamento, edit, change, move, reshape, handle, offset, contar, contagem, símbolos, count, counting, tally, symbols -->
<!-- source: 105c5177cf19 -->

# Medir comprimentos, áreas e ângulos, e contar

Pressione ⇧⌘M para mostrar a barra de ferramentas Measurement. Se o seu desenho estiver em escala, [defina a escala](drawing-scale.md) primeiro.

Aumente o zoom antes de medir para ter mais precisão. Pressionar Escape cancela uma medição em andamento. Pressione Escape de novo, ou clique na ferramenta selecionada, para largar a ferramenta.

## Ferramentas de medição

| Ferramenta | Como usar |
| --- | --- |
| Linear Dimension | Arraste de um ponto ao outro. |
| Perimeter | Clique em cada ponto ao longo do caminho. Pressione Return ou clique duas vezes para terminar. |
| Polygon Area | Clique em cada canto. Pressione Return, clique duas vezes ou clique no primeiro ponto para fechar a forma. |
| Vertex Angle | Clique em um ponto da primeira linha, depois no canto e, por fim, em um ponto da segunda linha. |
| Count | Digite o que está contando na caixa de grupo, como Tomadas, e clique em cada um. |

## Contar itens em um desenho {#count-things-on-a-drawing}

Escolha a ferramenta Count e digite um nome de grupo na caixa ao lado, como Tomadas ou Portas tipo A, ou escolha no menu ao lado da caixa um grupo que já existe no documento. Cada clique coloca um marcador, um ponto na cor da barra Measurement, e a barra mostra quantos desse grupo há na página. Mude o nome do grupo para contar outra coisa; cada grupo é contado separadamente. Use uma cor diferente para cada grupo para distingui-los na página.

Para mover um marcador, arraste-o com a ferramenta Select. Para remover um, clique nele com o botão direito e escolha Delete Count Marker. A [tabela de levantamento](takeoff.md) mostra quantos de cada grupo há em cada página, com totais. Os marcadores são salvos no PDF como pequenos círculos, então outros apps também os mostram.

## Desenhar com precisão

- **Ortho Lock** mantém as linhas em 0°, 45° e 90°. Mantenha ⇧ pressionada para invertê-lo em uma única linha: para medir em qualquer ângulo enquanto ele está ativado, ou para manter uma linha reta enquanto está desativado.
- **Vertex Magnetic Snapping** encaixa o cursor em cantos e extremidades do desenho.
- **Guias e grade:** com View > Rulers and Grid > Snap to Guides and Grid ativado, os pontos se encaixam nas guias que você arrastou das réguas e na grade enquanto ela estiver visível. Consulte [Réguas, barra de status e Inspector](rulers-and-inspector.md).
- **A barra de status** (View > Show Status Bar) mostra mais de uma medição enquanto você a desenha do que o seu rótulo: o ângulo e quanto ela avança na horizontal e na vertical, ou o perímetro de uma área até o momento.

## Alterar uma medição

Escolha **Select**, a seta no início da barra Measurement, ou pressione Escape para largar a ferramenta de medição. Aponte para uma medição e um contorno tracejado a mostra; clique nela para selecioná-la. Clique com ⇧ pressionada para selecionar várias, ou mantenha ⌥ pressionada e arraste sobre elas. Com uma ferramenta de medição em uso, um clique mede de novo.

Uma medição selecionada tem alças nos seus pontos.

| Para | Faça o seguinte |
| --- | --- |
| Mover um ponto | Arraste a alça dele. Ortho Lock e o encaixe funcionam como ao medir. |
| Mover a medição inteira | Arraste a linha dela ou pressione as teclas de seta (com ⇧ ela se move 10 pontos). |
| Aproximar ou afastar uma linha de cota do que ela mede | Arraste o rótulo dela ou, depois que ela estiver afastada dos pontos, a própria linha de cota. |
| Alterar a cor | Escolha uma cor com o botão de cor na barra de ferramentas Measurement. |
| Mudar a espessura da linha | Escolha ou digite uma espessura na caixa de espessura da barra Measurement. |

O valor é calculado de novo enquanto você arrasta. Arraste além da borda da janela para rolar, se a medição for maior que a visualização. Escolha Edit > Undo para deixar uma medição como estava. Medições já salvas no PDF também podem ser alteradas.

Para selecionar uma área, clique na borda dela: clicar dentro dela seleciona o texto que está ali.

## Alterar a aparência das medições

Use o botão de cor e a caixa de espessura na barra de ferramentas Measurement antes de medir. Escolha uma espessura em pontos ou digite uma, de 0,1 a 72 pontos. As novas medições são cinza, com 1,5 ponto de espessura, até você escolher outra coisa. O VectorPDF se lembra da sua escolha, e a barra Markup mantém suas próprias cores e espessuras. Para alterar a cor ou a espessura de uma medição que você já fez, selecione-a e escolha uma cor ou espessura na barra Measurement. A espessura é salva no PDF.

## Manter ou remover medições

As medições são anotações, armazenadas no PDF quando você [salva](save.md). Para apagar uma medição, clique nela com o botão direito e escolha o comando de apagar, como Delete Dimension, Delete Area Takeoff ou Delete Count Marker.

Para listar todas as suas medições, consulte a [tabela de levantamento](takeoff.md).

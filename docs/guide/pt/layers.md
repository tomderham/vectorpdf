<!-- keywords: camadas, camada, conteúdo opcional, CAD, plantas, desenhos, mostrar, ocultar, visibilidade, marcações, anotações, nova camada, renomear camada, apagar camada, configuração de camadas, configurações, estados de camada, plotagem, layers, layer, optional content, OCG, AutoCAD, Revit, show, hide, visibility, markups, annotations, new layer, rename layer, delete layer, layer configuration, configurations, layer states, plot -->
<!-- source: 4525c1273cca -->

# Mostrar e ocultar camadas

Desenhos exportados de programas de CAD e de projeto costumam colocar cada parte de uma prancha em sua própria camada: paredes, elétrica, hidráulica, cotas, nuvens de revisão. Você pode mostrar ou ocultar cada uma.

A aba Layers aparece na parte superior da barra lateral somente quando o documento tem camadas. Para dar a um documento sua primeira camada, consulte [Adicionar, renomear e apagar camadas](#add-rename-and-delete-layers).

- **Mostrar ou ocultar uma camada:** clique na caixa de seleção dela. A página é redesenhada na hora.
- **Escolher uma de um grupo:** alguns documentos agrupam camadas para que só uma apareça por vez, como os idiomas ou as escalas de uma prancha. Elas têm botões redondos; escolher uma oculta as outras.
- **Títulos:** agrupam as camadas listadas abaixo deles e não podem ser ocultados.
- **Camadas bloqueadas:** têm um cadeado ao lado. O documento não permite mostrá-las nem ocultá-las.

As camadas que você oculta também ficam de fora quando você [imprime](print.md), [seleciona texto](select-text.md), [pesquisa](search.md), [exporta um PDF nivelado](export.md#flattened-pdf) ou [pergunta ao Agent](agent.md), então você trabalha só com o que vê.

## Escolher uma configuração de camadas

Alguns documentos vêm com mais de uma forma de mostrar suas camadas, como uma para plotagem, uma para cada disciplina ou uma para cada idioma. Neles, a parte de cima da aba Layers mostra a configuração em uso, no lugar do número de camadas. Ela é **Default** até você escolher outra, a menos que o documento dê nome à sua configuração padrão.

Clique nela e escolha uma configuração. As camadas são mostradas e ocultadas como ela indica, e listadas como ela as lista.

Se depois você mostrar ou ocultar uma camada, **(Changed)** aparece após o nome da configuração. Escolha a configuração de novo para restaurar as camadas dela.

## Colocar anotações em uma camada

As anotações também podem ficar em uma camada, para que sejam mostradas e ocultadas com ela. Outros apps que leem camadas, como o Acrobat e o Bluebeam, as mostram e ocultam do mesmo jeito.

- **Escolher para onde vão as novas anotações:** na [barra de ferramentas Markup](draw-and-notes.md) ou na [barra de ferramentas Measurement](measure.md), clique no menu de camadas (ele mostra **No Layer** até você escolher uma) e escolha uma camada. Tudo o que você criar a partir daí vai para ela, até você escolher outra camada ou **No Layer**. Você também pode clicar com o botão direito em uma camada na aba Layers e escolher **Put New Annotations Here**. A camada das novas anotações tem um lápis ao lado.
- **Mover uma anotação para outra camada:** clique nela com o botão direito e escolha **Layer** e, depois, uma camada, ou **None** para tirá-la de qualquer camada.
- **Adicionar uma camada sua:** consulte [Adicionar, renomear e apagar camadas](#add-rename-and-delete-layers).

O menu de camadas aparece somente quando um documento tem camadas, então as barras de ferramentas dos outros documentos não mudam.

Anotações em uma camada oculta somem da página, da [aba Comments](draw-and-notes.md#see-all-annotations) e da [tabela de levantamento](takeoff.md), e não podem ser selecionadas nem apagadas com a borracha. A tabela Annotations continua listando-as, com a camada delas.

Se você escolher uma camada oculta para as novas anotações, ela é mostrada, para que o que você cria não desapareça. Undo devolve uma anotação à camada em que ela estava.

## Adicionar, renomear e apagar camadas {#add-rename-and-delete-layers}

Revisores costumam colocar suas marcações em camadas próprias, como uma por disciplina ou por rodada de revisão, até em desenhos que vieram sem camadas. Cada um destes comandos altera o documento, e Undo o desfaz.

- **Adicionar uma camada:** escolha Edit > New Layer… e dê um nome a ela. Funciona em qualquer PDF, então é assim que um documento ganha a primeira camada; em seguida aparecem a aba Layers e os menus de camadas. As novas anotações vão para a nova camada. Em um documento que já tem camadas, você também pode clicar em **+** na parte superior da aba Layers, ou escolher **New Layer…** no menu de camadas.
- **Renomear uma camada:** escolha Edit > Rename Layer…, escolha a camada e digite o novo nome.
- **Apagar uma camada:** escolha Edit > Delete Layer… e, depois, a camada. As anotações dela continuam na página, sem camada. Só é possível apagar camadas que contêm apenas anotações: apagar uma em que está o próprio desenho deixaria essa parte do desenho sempre visível, por isso elas não aparecem na lista.

## O que é salvo

As camadas que você adiciona, renomeia ou apaga são salvas com o documento, assim como as camadas em que estão as anotações.

Quais camadas estão sendo mostradas e qual configuração você escolheu não são salvos com o documento. Na próxima vez que você abri-lo, as camadas serão mostradas como o próprio documento define, e quem receber o documento verá o mesmo.

> **Nota:** Um documento de uma ou duas páginas com camadas abre na aba Layers, a menos que você tenha ocultado a barra lateral para ele. Use o botão da barra lateral na barra de ferramentas para mostrá-la.

<!-- keywords: buscar, busca, localizar, localizar próximo, maiúsculas e minúsculas, palavra inteira, busca inteligente, padrões ignorados, expressão regular, etiquetas, pesquisas recentes, histórico de pesquisa, seção, sumário, índice, lado direito, ao lado do sumário, mover a busca, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, recent searches, search history, section, outline, table of contents, right side, beside the outline, move search, PDF -->
<!-- source: 9e3d931100aa -->

# Buscar em um documento

## Encontrar texto

1. Pressione ⌘F. O VectorPDF mostra a aba Search na barra lateral, ou à direita da janela se você a [moveu para lá](#see-results-beside-the-outline).
2. Digite o que você procura. Os resultados aparecem à medida que são encontrados, a partir da página em que você está.

Os resultados são listados por página, cada um com o texto ao redor, e todas as correspondências ficam realçadas no documento. Em um documento com [sumário](outline-and-thumbnails.md), os resultados também são agrupados pela seção em que estão. O nome da seção fica no topo da lista enquanto você rola pelos resultados dela. Para ver de quais seções maiores ela faz parte, mantenha o ponteiro sobre o nome.

## Navegar entre os resultados

| Para | Faça o seguinte |
| --- | --- |
| Ir para o próximo resultado | Pressione Return ou ⌘G, ou clique na seta para baixo |
| Ir para o resultado anterior | Pressione ⇧Return ou ⇧⌘G, ou clique na seta para cima |
| Ir para qualquer resultado | Clique nele |
| Percorrer a lista | Clique em um resultado e pressione as teclas de seta |

Clique em um resultado com o botão direito para [criar uma âncora](anchors.md) a partir dele ou abri-lo em uma nova janela.

## Ver os resultados ao lado do sumário {#see-results-beside-the-outline}

Para ver os resultados e o sumário ao mesmo tempo, clique no botão de opções ao lado do campo de busca e escolha Show Search on Right. A busca passa para o lado direito da janela e a barra lateral mostra o sumário, ou as miniaturas das páginas se o documento não tiver sumário. Cada item do sumário com resultados mostra quantos tem, e a contagem da seção com o resultado atual fica realçada. Uma seção com as subseções ocultas também conta os resultados dentro delas. Clique em um item do sumário e a lista de resultados rola até os resultados dessa seção (ou os das subseções, se ela não tiver nenhum próprio), enquanto a página mostra o título da seção; o resultado atual continua o mesmo até você clicar em um.

Cada documento lembra de que lado você colocou a busca. Para devolvê-la à barra lateral, escolha Show Search on Right novamente para desativá-la. Para ocultá-la enquanto estiver à direita, clique no botão de fechar (×) ao lado dela. Para mostrá-la de novo, pressione ⌘F ou clique no botão Search no topo da barra lateral.

A busca divide o lado direito com o [Inspector](rulers-and-inspector.md#the-inspector). Quando os dois estão abertos, alterne entre eles com os botões Search e Inspector no topo.

## Pesquisar novamente algo que já pesquisou

Cada documento lembra as últimas 10 pesquisas em que foi para um resultado. Para pesquisar uma delas novamente:

- Clique na lupa do campo de pesquisa e escolha-a, ou
- Com o campo de pesquisa vazio, clique nela na lista Recent Searches, abaixo do campo.

O VectorPDF vai para o resultado mais próximo. Para esquecer as pesquisas de um documento, escolha Clear Recent Searches na lupa ou clique em Clear acima da lista. Aplicar tarjas a um documento também apaga as pesquisas recentes dele.

## Opções de busca {#search-options}

Clique no botão de opções ao lado do campo de busca:

- **Match Case:** encontra somente texto com as mesmas maiúsculas e minúsculas.
- **Whole Word:** não encontra correspondências dentro de palavras maiores.
- **Smart Search:** fica ativado, a menos que você o desative. Espaços, hifens, travessões e quebras de linha são tratados como equivalentes, de modo que “end-to-end” também encontra “end to end”, mesmo em uma quebra de linha. Aspas retas e curvas também são tratadas como equivalentes.
- **Show Search on Right:** move a busca da barra lateral para a direita da janela, para que você possa vê-la [ao lado do sumário](#see-results-beside-the-outline).

## Ignorar elementos que atrapalham o texto {#ignore-clutter-in-the-text}

Alguns documentos colocam marcadores no meio das frases, como números de citação, o que impede que uma expressão seja encontrada. O Smart Search pode ignorá-los.

1. Escolha VectorPDF > Settings e clique em Advanced.
2. Ao lado de Ignored Search Patterns, clique em Edit.
3. Adicione um dos padrões prontos ou sua própria expressão regular e ative-o.

Os padrões prontos abrangem citações numéricas como [12], símbolos de marca registrada, paginação com asterisco como *123 e etiquetas de comentários do IEEE 802.11.

## Documentos digitalizados

Páginas digitalizadas não têm texto para buscar até serem reconhecidas. Consulte [Buscar e selecionar texto em páginas digitalizadas](scanned-pages.md).

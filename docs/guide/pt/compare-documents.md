<!-- keywords: comparar, comparação, diferenças, revisão, versões, alterações, lado a lado, rolagem sincronizada, renumeração, números de página, referências cruzadas, sumário, compare, comparison, diff, difference, differences, revision, revisions, redline, changes, versions, side by side, synchronized scrolling, scroll together, renumbering, page numbers, cross-references, table of contents -->
<!-- source: 84d22a753af8 -->

# Comparar dois documentos

Compare Documents mostra duas versões de um documento lado a lado, com o texto que mudou destacado em ambas. Ao rolar uma, a outra rola até o mesmo texto, mesmo onde páginas foram adicionadas ou removidas entre as versões.

## Abrir uma comparação

1. Escolha File > Compare Documents.
2. Escolha o documento original (Original) e o revisado (Revised). Cada menu lista os documentos que você tem abertos; escolha Choose File para escolher outro. O documento em primeiro plano começa como o original. Clique em Swap para trocá-los.
3. Clique em Compare.

Você também pode clicar com o botão direito no título do documento, ou numa parte vazia da barra de ferramentas, e escolher um documento em Compare With. Isso compara o documento em primeiro plano com o que você escolher.

A comparação abre numa nova aba, com o original à esquerda e a revisão à direita. Ali os dois são somente leitura. Para editar um deles, abra-o na sua própria aba.

## Ler as alterações

- As palavras removidas do original são destacadas em vermelho, à esquerda.
- As palavras adicionadas na revisão são destacadas em verde, à direita.
- Onde houve texto adicionado em um lado só, uma barra fina no outro lado marca onde ele estaria.
- O texto que é igual nos dois mas está noutro lugar aparece sublinhado a azul dos dois lados, como uma tabela que fica do outro lado de uma quebra de página, ou uma cláusula que foi movida. São precisas dez palavras seguidas ou mais. O texto movido não conta como alteração; o topo da aba Changes indica quantas passagens estão noutro lugar.

A aba Changes da barra lateral lista todas as alterações: palavras removidas riscadas em vermelho, palavras adicionadas em verde e o número da página na revisão. Clique numa alteração para ir até ela nos dois documentos.

Para percorrer as alterações, clique na seta para cima ou para baixo no topo da aba Changes, escolha Go > Previous Change ou Go > Next Change, ou pressione ⌥⌘Up Arrow ou ⌥⌘Down Arrow. A aba mostra em qual alteração você está, como 3 of 12. Essa alteração fica destacada com mais intensidade e selecionada na lista.

Só o texto é comparado. Alterações de formatação, imagens ou desenhos não são mostradas. Cabeçalhos, rodapés e números de página são deixados de fora, para não aparecerem como alterações quando as páginas mudam de lugar.

## Encontrar uma seção ou uma palavra

As abas Outline & Thumbnails e Search da barra lateral funcionam na revisão, como em qualquer aba. Vá para uma seção ou para um resultado da busca, e o original acompanha até o mesmo texto.

## Rolar e ampliar juntos

A linha a cerca de um terço da altura de cada lado mostra o mesmo texto. Quando um lado tem texto que o outro não tem, o outro espera até você passar por ele. Você pode rolar qualquer um dos lados; o outro acompanha.

Ampliar um lado amplia os dois, e o texto que você está lendo fica onde está. Com ampliação maior que a largura da página, rolar um lado na horizontal rola o outro também, para que os dois mostrem a mesma parte da página.

## Opções de comparação

No topo da aba Changes, escolha Ignore Case ou Ignore Punctuation para deixar de fora diferenças de maiúsculas ou de pontuação. Aspas tipográficas e retas, e os diferentes tipos de travessão, contam sempre como iguais.

### Ignorar a renumeração

Quando uma cláusula, figura ou tabela é adicionada ou removida, tudo o que vem depois é numerado de novo, e todos os números de página seguintes mudam. Num documento longo, a maioria das alterações pode ser números novos no sumário, na lista de figuras e nas referências cruzadas. Ignore Renumbering, que vem ativado, deixa-os de fora:

- Uma entrada do sumário ou de uma lista de figuras, ou uma referência cruzada como “ver 9.4.2.18”, não conta como alterada quando leva ao mesmo lugar nas duas versões, mesmo que o seu número ou número de página seja novo.
- No lugar para onde leva, o próprio número do título ou da legenda também não conta como alterado quando mudou da mesma forma. Por exemplo, “Figure 9-806” que passa a “Figure 9-809”.

O que conta como o mesmo lugar vem das ligações dos documentos, não do aspeto dos números. Uma referência cruzada que agora leva a outro lugar continua a aparecer como alteração, tal como um número que não faz parte de uma ligação, por exemplo “Table 9-12” escrito como texto simples. Um título reescrito continua a aparecer como alterado no próprio título, mesmo quando a sua entrada no sumário não aparece.

Ignore Renumbering precisa de documentos com ligações internas, que a maioria dos processadores de texto e apps de paginação cria para o sumário e as referências cruzadas. Não está disponível quando nenhum dos documentos as tem. Um PDF guardado de novo por uma app que descarta ligações não tem nenhuma, mesmo que o original tivesse.

Para ver todos os números que mudaram, desative Ignore Renumbering.

## Se a comparação não ajudar

- **Um documento não tem texto para comparar:** páginas digitalizadas não têm texto até que ele seja reconhecido. Consulte [Buscar e selecionar texto em páginas digitalizadas](scanned-pages.md).
- **Estes documentos têm pouco texto em comum:** talvez não sejam versões do mesmo documento.

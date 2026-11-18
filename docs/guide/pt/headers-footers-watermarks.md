<!-- keywords: cabeçalho, cabeçalhos, rodapé, rodapés, números de página, numeração de páginas, Bates, números Bates, numeração Bates, marca d’água, marcas d’água, RASCUNHO, CONFIDENCIAL, jurídico, header, headers, footer, footers, page numbers, page numbering, Bates numbers, Bates numbering, watermark, watermarks, DRAFT, CONFIDENTIAL, stamp text, legal, discovery, PDF -->
<!-- source: 7e05ab7492d9 -->

# Cabeçalhos, rodapés, números Bates e marcas d’água

Você pode colocar texto no topo e na parte de baixo das páginas, como um título, números de página ou números Bates, e uma marca d’água como RASCUNHO ou CONFIDENCIAL atravessando-as. Escolha Edit > Headers, Footers and Watermark, preencha as partes que quiser e clique em **Add**.

O VectorPDF guarda no documento o que você escolheu, então depois você pode alterar ou remover os cabeçalhos, rodapés e a marca d’água. Escolha Edit > Headers, Footers and Watermark de novo, faça as alterações e clique em **Update**. Para remover tudo, clique em **Remove All**.

As alterações passam a fazer parte do arquivo quando você [salva](save.md).

## Cabeçalho e rodapé

Digite em qualquer uma das seis caixas: à esquerda, no centro e à direita do cabeçalho e do rodapé. Deixe uma caixa vazia para não colocar nada nela.

Para adicionar um número de página ou outro valor que muda de uma página para outra, clique em uma caixa e escolha no menu **Insert**:

| Insert | Mostra |
| --- | --- |
| Page Number | O número da página, contando a partir da primeira página marcada. Consulte [Páginas e números](#pages-and-numbers). |
| Page Count | Quantas páginas o documento tem |
| Bates Number | O número Bates da página |
| Date | A data de hoje |
| File Name | O nome do arquivo do documento |

Cada um aparece na caixa como uma palavra entre colchetes angulares duplos, como `<<page>>`. Por exemplo, digite `Página `, insira Page Number, digite ` de ` e insira Page Count para obter “Página 3 de 12”.

Você pode escolher a fonte, o tamanho e a cor do texto, e as margens: a distância do cabeçalho até o topo da página, do rodapé até a parte de baixo, e de ambos até as laterais, em pontos (72 pontos são uma polegada).

## Marca d’água

Digite o texto da marca d’água. Pressione Return para uma segunda linha. Depois escolha:

- **Font** e **Color**.
- **As large as fits the page**, ou um tamanho à sua escolha.
- **Opacity:** o quanto ela aparece. Uma marca d’água clara deixa a página legível.
- **Angle:** horizontal, diagonal ou vertical.
- **Behind the page's content:** desenha a marca d’água sob o texto e as imagens da página, em vez de sobre eles. Uma página com fundo, como uma página digitalizada, esconde uma marca d’água que esteja atrás dela.

## Páginas e números {#pages-and-numbers}

- **Pages:** todas as páginas, páginas ímpares ou pares, e de uma página até outra. Deixe From ou To vazio para a primeira ou a última página.
- **First page marked is page:** o número que Page Number dá à primeira página marcada. Os números aumentam de um em um a cada página marcada.
- **Bates numbers:** um prefixo, como o nome de um caso ou de uma empresa, o número de dígitos, o número inicial e um sufixo. Os números Bates aumentam de um em um a cada página marcada e são completados com zeros, como ACME-000001. Insira Bates Number em um cabeçalho ou rodapé para mostrá-los.

## Bom saber

- Cabeçalhos, rodapés e marcas d’água fazem parte da página, não são [anotações](draw-and-notes.md), então são impressos e aparecem em outros apps. Eles são marcados como decoração da página, que os leitores de tela podem pular. Você pode buscar e selecionar o texto deles.
- As margens são medidas na página como ela é exibida, então, em uma página que foi girada, o cabeçalho continua no topo.
- O VectorPDF só pode alterar ou remover os cabeçalhos, rodapés e marcas d’água que ele adicionou. Os adicionados por outros apps fazem parte do conteúdo da página.
- Adicioná-los a um documento [assinado digitalmente](digital-signatures.md) altera o que foi assinado, então as assinaturas dele deixam de ser válidas.

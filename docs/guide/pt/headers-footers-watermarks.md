<!-- keywords: logotipo, marca d’água com imagem, vários arquivos, chinês, hindi, árabe, cabeçalho, cabeçalhos, rodapé, rodapés, números de página, numeração de páginas, Bates, números Bates, numeração Bates, marca d’água, marcas d’água, RASCUNHO, CONFIDENCIAL, jurídico, header, headers, footer, footers, page numbers, page numbering, Bates numbers, Bates numbering, watermark, watermarks, DRAFT, CONFIDENTIAL, stamp text, legal, discovery, PDF, Chinese, Japanese, Korean, Hindi, Arabic, any language, logo, picture watermark, image watermark -->
<!-- source: 05436b7b8113 -->

# Cabeçalhos, rodapés, números Bates e marcas d’água

Você pode colocar texto no topo e na parte de baixo das páginas, como um título, números de página ou números Bates, e uma marca d’água como RASCUNHO ou CONFIDENCIAL atravessando-as. Escolha Edit > Headers, Footers and Watermark, preencha as partes que quiser e clique em **Add**. Uma prévia ao lado dos ajustes mostra a página que você está lendo como ela vai ficar, com seus próprios números de página e Bates; use as setas abaixo dela para ver outras páginas.

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

O texto pode estar em qualquer idioma, como chinês, hindi ou árabe. Onde a fonte escolhida não tiver os caracteres, é usada uma fonte do seu Mac que os tenha, e os caracteres usados são salvos no documento para que ele apareça igual em qualquer lugar.

## Marca d’água

Uma marca d’água é um texto ou uma imagem. Para texto, digite-o; pressione Return para uma segunda linha. Para uma imagem, como um logotipo, escolha **Picture**, clique em **Choose Picture** e ajuste a largura dela como fração da largura da página. Depois escolha:

- **Font** e **Color**.
- **As large as fits the page**, ou um tamanho à sua escolha.
- **Opacity:** o quanto ela aparece. Uma marca d’água clara deixa a página legível.
- **Angle:** horizontal, diagonal ou vertical.
- **Behind the page's content:** desenha a marca d’água sob o texto e as imagens da página, em vez de sobre eles. Uma página com fundo, como uma página digitalizada, esconde uma marca d’água que esteja atrás dela.

## Páginas e números {#pages-and-numbers}

- **Pages:** todas as páginas, páginas ímpares ou pares, e de uma página até outra. Deixe From ou To vazio para a primeira ou a última página.
- **First page marked is page:** o número que Page Number dá à primeira página marcada. Os números aumentam de um em um a cada página marcada.
- **Bates numbers:** um prefixo, como o nome de um caso ou de uma empresa, o número de dígitos, o número inicial e um sufixo. Os números Bates aumentam de um em um a cada página marcada e são completados com zeros, como ACME-000001. Insira Bates Number em um cabeçalho ou rodapé para mostrá-los.

## Marcar vários arquivos

Para numerar um conjunto de documentos, por exemplo para um processo judicial, com números Bates que continuam de um arquivo para o seguinte, configure as marcas e clique em **Apply to Other Files**. Escolha os PDFs e depois uma pasta para as cópias marcadas; os arquivos em si não são alterados. Eles são marcados na ordem dos nomes, então dê nomes na ordem em que devem ser numerados. No fim, o VectorPDF informa quais números Bates foram usados e lista os arquivos que não conseguiu marcar, como um que precise de senha.

## Bom saber

- Cabeçalhos, rodapés e marcas d’água fazem parte da página, não são [anotações](draw-and-notes.md), então são impressos e aparecem em outros apps. Eles são marcados como decoração da página, que os leitores de tela podem pular. Você pode buscar e selecionar o texto deles.
- As margens são medidas na página como ela é exibida, então, em uma página que foi girada, o cabeçalho continua no topo.
- Cabeçalhos, rodapés e marcas d’água adicionados por outros apps, como o Adobe Acrobat, também podem ser removidos, se o app os tiver marcado como tal (a maioria faz isso): quando o VectorPDF encontra algum, **Remove them** aparece em Pages & Numbers, e a prévia mostra a página sem eles. Depois de removidos, eles só voltam se você reverter para o documento salvo.
- Adicioná-los a um documento [assinado digitalmente](digital-signatures.md) altera o que foi assinado, então as assinaturas dele deixam de ser válidas.

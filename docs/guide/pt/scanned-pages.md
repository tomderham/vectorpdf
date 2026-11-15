<!-- keywords: digitalizar, digitalizado, digitalizada, digitalização, reconhecimento de texto, reconhecer texto, imagem, OCR, selecionar, copiar, realçar, scan, scanned, scans, text recognition, recognize text, image, Run OCR, select, copy, highlight, PDF pesquisável, salvar texto, camada de texto, idioma, searchable PDF, save text, text layer, language -->
<!-- source: 8b77a345a44e -->

# Buscar e selecionar texto em páginas digitalizadas

Uma página digitalizada é uma imagem de um texto. O VectorPDF pode reconhecer o texto com o reconhecimento óptico de caracteres (OCR), no seu Mac, para que você possa fazer buscas nele, selecioná-lo e marcá-lo.

## Como funciona

Quando você abre um documento, o VectorPDF procura páginas digitalizadas entre as 50 primeiras páginas e reconhece o texto delas em segundo plano. Quando há mais trabalho a fazer, a aba Search mostra quantas páginas digitalizadas foram encontradas.

- **Para reconhecer todas as páginas digitalizadas encontradas,** clique em **Run OCR** na aba Search.
- Uma busca também as reconhece, portanto você pode simplesmente começar a buscar.

Os realces acompanham o texto, mesmo que a página tenha sido digitalizada levemente inclinada.

O texto é reconhecido nos idiomas dos ajustes Idioma e Região do seu Mac que o reconhecimento suporta, ou em inglês se ele não suportar nenhum deles.

## Selecionar texto reconhecido

Depois que uma página é reconhecida, você pode [selecionar e copiar](select-text.md) o texto dela e [realçá-lo, sublinhá-lo ou riscá-lo](text-markup.md) como em qualquer outra página. O reconhecimento pode levar um momento, e as páginas após as 50 primeiras precisam antes de Run OCR ou de uma busca.

O reconhecimento pode cometer erros, portanto confira tudo o que você copiar e que precise ser exato. As seleções começam e terminam de forma precisa nas bordas das palavras. Dentro de uma palavra, as extremidades são aproximadas.

> **Nota:** O texto reconhecido é usado enquanto o documento está aberto e não é salvo no PDF, a menos que você escolha salvá-lo (veja abaixo). As marcações que você adiciona são salvas. Se você tarjar ou girar uma página, o texto dela será reconhecido novamente.

## Salvar o texto reconhecido no PDF {#save-the-recognized-text-in-the-pdf}

Para que um PDF digitalizado também possa ser pesquisado em outros apps, como Pré-Visualização, Spotlight e Acrobat, salve nele o texto reconhecido. O texto é adicionado como uma camada invisível sob cada página digitalizada, no lugar onde foi reconhecido, então as páginas continuam com a mesma aparência.

- **Para salvá-lo no documento,** escolha File > Save with Recognized Text ou clique em **Save in PDF** na aba Search depois que o texto for reconhecido. Suas outras alterações também são salvas.
- **Para salvá-lo em uma cópia,** escolha File > Export Document As > Searchable PDF. O documento aberto não é alterado.

Em ambos os casos, o VectorPDF primeiro reconhece as páginas digitalizadas que ainda não reconheceu, mostrando o progresso. Cada página leva um momento. Você pode clicar em Cancel, e nada é salvo.

Só recebem texto as páginas que não têm texto próprio. Quando o texto está no arquivo, essas páginas deixam de ser tratadas como digitalizadas: o VectorPDF seleciona e busca o texto salvo, como fazem outros apps.

> **Importante:** O reconhecimento pode cometer erros, e o texto salvo vai para onde o arquivo for: índices de busca, texto copiado e leitores de tela. Verifique se o texto está correto antes de confiar nele, ou salve uma cópia. Salvar no documento também o reabre a partir do arquivo, então não é possível desfazer as alterações feitas antes de salvar.

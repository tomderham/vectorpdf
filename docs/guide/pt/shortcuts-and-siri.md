<!-- keywords: Atalhos, Siri, Spotlight, automação, ação, ações, perguntar, buscar, extrair páginas, abrir documento, fluxo de trabalho, Shortcuts, automation, action, actions, App Intents, ask, search, extract pages, open document, workflow -->
<!-- source: 0598b760c342 -->

# Usar o VectorPDF com Atalhos e a Siri

O VectorPDF adiciona ações ao app Atalhos, para que você possa usá-las nos seus próprios atalhos e pelo Spotlight e pela Siri.

| Ação | O que faz |
| --- | --- |
| Ask About Document | Faz uma pergunta ao [Agent](agent.md) e retorna a resposta, com citações de página |
| Search Document | Encontra texto, como o campo de busca, e retorna cada ocorrência com o número da página |
| Extract Pages | Cria um novo PDF com algumas páginas de um PDF, como `1-3, 5` |
| Open Document | Abre um documento no VectorPDF, em uma página, se você indicar uma |

Se você não escolher um documento para Ask, Search ou Extract Pages, a ação usa o documento que está na frente no VectorPDF.

## Usar uma ação em um atalho

1. Abra o app Atalhos e crie ou abra um atalho.
2. Busque VectorPDF na lista de ações e arraste uma ação para o seu atalho.
3. Preencha a ação. Para usar um arquivo de uma etapa anterior do atalho, como o de uma ação que obtém um arquivo, clique em Document e escolha-o.

Cada ação repassa o que retorna: a resposta, a lista de ocorrências ou o novo PDF. Depois, você pode enviá-lo para outra ação, como uma que cria um PDF, adiciona a uma nota ou envia uma mensagem.

Se as ações do VectorPDF não aparecerem, abra o VectorPDF uma vez e depois encerre e abra novamente o Atalhos.

## Pedir à Siri

Você pode dizer ou digitar estas frases para a Siri. A Siri pede o que mais precisar, como a sua pergunta. As frases estão em inglês, porque o VectorPDF ainda não foi traduzido, então funcionam quando o idioma da Siri é inglês:

- "Ask VectorPDF about this document"
- "Search this document in VectorPDF"
- "Extract pages in VectorPDF"
- "Open a document in VectorPDF"

Você também pode encontrar as ações digitando os nomes delas no Spotlight.

## Sobre cada ação

- **Ask About Document** abre o documento no VectorPDF se ele não estiver aberto, atrás da janela em que você está trabalhando. A pergunta e a resposta também aparecem na aba Ask About This Document do documento, para que você possa ler as fontes e fazer outras perguntas. É preciso que o Agent esteja ativado, e a resposta vem do mecanismo que você escolheu em [Escolher como o Agent responde](agent-engines.md). Quando não é possível gerar respostas, a ação retorna os trechos mais relevantes.
- **Search Document** usa a Smart Search e os seus [Ignored Search Patterns](search.md#ignore-clutter-in-the-text), com Match Case e Whole Words se você os ativar. Retorna até 100 ocorrências e informa quantas há no total. Busca em um documento aberto como ele está no VectorPDF, com as alterações não salvas e apenas as camadas mostradas; outros documentos são buscados sem abri-los.
- **Extract Pages** aceita páginas e intervalos separados por vírgulas. Um intervalo como `5-` vai até a última página, e `3-1` dá as páginas em ordem inversa. A ação lê o arquivo como foi salvo pela última vez e não o altera. O novo PDF recebe o nome do documento e das páginas, como "Report (Pages 1-3, 5).pdf".
- **Open Document** traz a aba do documento para a frente se ele já estiver aberto.

Um documento protegido por senha precisa estar aberto no VectorPDF, com a senha digitada, para que o Search Document possa buscar nele. O Extract Pages não pode usar documentos protegidos por senha.

> **Nota:** O que uma ação retorna vai para o Atalhos ou para a Siri e, de lá, para a próxima etapa do seu atalho. O Ask About Document envia apenas o que o Agent enviaria se você perguntasse no VectorPDF. Consulte [Privacidade](privacy.md).

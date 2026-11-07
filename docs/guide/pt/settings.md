<!-- keywords: ajustes, preferências, opções, atualizações, atualizar, verificar atualizações, navegador, autor, autor das anotações, armazenamento, espaço em disco, limpar, remover dados, apagar dados, desinstalar, settings, preferences, options, updates, update, check for updates, browser, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->
<!-- source: 91c5b0e9ab3d -->

# Ajustes

Escolha VectorPDF > Settings ou pressione ⌘,.

| Ajuste | O que faz |
| --- | --- |
| Annotation Author | O nome salvo nas suas anotações e respostas. Se estiver vazio, o VectorPDF usa o seu nome de usuário do Mac. |
| Use Agent | Mostra a aba [Ask About This Document](agent.md) na barra lateral, no macOS 26 ou posterior. |
| AI Synthesis Engine | Escolhe [o que redige as respostas do Agent](agent-engines.md), no macOS 27. |
| PDF Color | Define [a aparência das páginas](pdf-colors.md): Follow System, Light, Dark ou Sepia. |
| Open Links In | Escolhe o navegador para os links da web. |
| LaTeX (SyncTeX) | Escolhe o editor que abre o [código LaTeX](latex.md) quando você clica em um PDF com ⇧⌘ pressionadas. |
| Ignored Search Patterns | Lista o texto que o [Smart Search ignora](search.md#ignore-clutter-in-the-text). |
| Digital Stamp | Cria, altera ou apaga seu [carimbo](stamps.md). |
| Sync reading positions with iCloud | Mantém sua [página, zoom, âncoras](reading-positions.md) e [pesquisas recentes](search.md) nos seus outros Macs. |
| Storage | Mostra quanto espaço os dados do VectorPDF ocupam e permite [limpá-los](#free-up-space-or-remove-data). |
| Automatically check for updates | Verifica se há uma nova versão no GitHub cerca de uma vez por dia. Clique em Check Now para verificar a qualquer momento. |

## Liberar espaço ou remover dados {#free-up-space-or-remove-data}

Em Storage, os ajustes mostram quanto espaço cada tipo de dado ocupa:

- **Índices do Agent:** o que o Agent cria para responder a perguntas sobre um documento. Clique em Clear para apagá-los; o documento é indexado novamente na próxima vez que você usar o Agent com ele. O VectorPDF os mantém abaixo de 500 MB, apagando primeiro os usados há mais tempo, e apaga o índice de um documento quando o documento não existe mais.
- **Histórico de leitura:** a última página, o zoom, as âncoras e as pesquisas recentes de cada documento. Clique em Clear para esquecê-los, neste Mac e no iCloud.
- **Arquivos temporários:** cópias criadas ao editar, salvar, imprimir ou exportar, e atualizações baixadas. O VectorPDF apaga as que sobrarem na próxima vez que for aberto.

Para remover tudo o que o VectorPDF armazenou, clique em Remove All VectorPDF Data. Isso também remove seus ajustes, favoritos, Grupos de Abas, carimbo e chaves de API, e depois fecha o VectorPDF. Seus documentos não são alterados. Antes, salve ou feche os documentos com alterações não salvas.

## Atualizar o VectorPDF

Escolha VectorPDF > Check for Updates. Se houver uma nova versão, clique em Download. Quando o download terminar, clique em **Quit and Open Installer** e arraste o VectorPDF para a pasta Aplicativos.

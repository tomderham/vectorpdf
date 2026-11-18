<!-- keywords: salvar, salvar como, não salvo, compartilhar, alterações, reverter, última versão salva, recarregar, descartar alterações, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all, salvamento automático, recuperar, recuperação, falha, fechamento inesperado, autosave, recover, recovery, crash, quit unexpectedly -->
<!-- source: cdbdeb12d33f -->

# Salvar suas alterações

Marcações, dados de formulários, alterações de páginas e tarjamentos só são gravados no arquivo quando você salva. Uma janela com alterações não salvas mostra um ponto no botão de fechar.

| Para | Faça o seguinte |
| --- | --- |
| Salvar | Escolha File > Save ou pressione ⌘S |
| Salvar uma cópia com um novo nome | Escolha File > Save As ou pressione ⇧⌘S |
| Salvar uma cópia protegida por senha | Escolha File > [Save Encrypted with Password](passwords.md) ou pressione ⌥⌘S |

Se você fechar um documento com alterações não salvas, o VectorPDF perguntará se deseja salvá-las.

Um documento [assinado digitalmente](digital-signatures.md) é salvo adicionando suas alterações depois do que foi assinado, para que as assinaturas continuem válidas na medida em que as alterações forem permitidas.

## Descartar as alterações

Para descartar tudo o que foi feito desde a última vez que você salvou, escolha File > Revert to Saved. O VectorPDF pergunta primeiro e, em seguida, abre o arquivo como foi salvo pela última vez, na página que você estava lendo. Não é possível desfazer essa ação.

Para criar uma cópia menor de um documento, consulte [Optimized PDF](export.md#optimized-pdf).

## Se o VectorPDF fechar inesperadamente {#if-vectorpdf-quits-unexpectedly}

Enquanto um documento tem alterações não salvas, o VectorPDF mantém uma cópia dele no seu Mac, atualizada a cada 30 segundos, aproximadamente. Se o VectorPDF fechar inesperadamente, ele oferece as cópias na próxima vez que for aberto:

- **Open Recovered Copy** salva cada cópia ao lado do original, com o nome "(Recovered)", e a abre. O original não é alterado. Compare os dois e fique com o que preferir.
- **Decide Later** mantém as cópias e pergunta de novo na próxima vez.
- **Discard Changes** apaga as cópias.

A cópia é apagada quando você salva o documento, reverte para a versão salva ou o fecha sem salvar, e quando você encerra o VectorPDF. Documentos protegidos por senha não são copiados, porque a cópia não seria criptografada.

## Compartilhar um documento

Escolha File > Share para usar um serviço de compartilhamento do macOS, ou File > Show in Finder (⇧⌘R) para encontrar o arquivo. Na tela Start, clique em um documento com o botão direito para mostrá-lo no Finder.

## O que não é salvo no PDF

Alguns itens ficam no VectorPDF e não acompanham o arquivo: as [âncoras](anchors.md), sua [posição de leitura](reading-positions.md), a rotação da visualização e o texto reconhecido por [OCR](scanned-pages.md), a menos que você o [salve no PDF](scanned-pages.md#save-the-recognized-text-in-the-pdf).

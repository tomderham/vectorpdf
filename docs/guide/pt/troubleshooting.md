<!-- keywords: damaged, corrupt, unreadable, solução de problemas, problema, problemas, não funciona, ajuda, corrigir, suporte, troubleshooting, problem, problems, not working, help, fix, support -->
<!-- source: 0ca329d057c7 -->

# Solução de problemas

## Não consigo selecionar texto, seguir links ou usar as ferramentas de marcação

Verifique se não há uma ferramenta de Markup ou Measurement ativa. Pressione Escape, ou clique de novo na ferramenta selecionada, para voltar a selecionar texto.

## Uma busca não encontra nada

- As páginas podem estar digitalizadas. Consulte [Buscar e selecionar texto em páginas digitalizadas](scanned-pages.md).
- Verifique se Match Case e Whole Word estão desativados nas [opções de busca](search.md#search-options) e se Smart Search está ativado.
- Se houver marcadores interrompendo o texto, adicione um [padrão ignorado](search.md#ignore-clutter-in-the-text).

## Manter ⌘ pressionada não mostra uma pré-visualização

O Link Peek funciona em links do documento e em links da web para documentos abertos em outra aba. Referências em texto simples não são links, portanto clique nelas com o botão direito. Consulte [Referências entre documentos](cross-document-references.md).

A janela do VectorPDF também precisa ser a janela ativa.

## Uma referência a outro documento não é encontrada

Abra o outro documento como uma aba na mesma janela. Janelas separadas não são incluídas na busca.

## Um documento aparece como danificado

Se o VectorPDF não encontrar nenhuma página em um arquivo, ele informa que não foi possível abri-lo. O arquivo pode estar danificado ou incompleto, ou usar recursos que o VectorPDF não consegue ler. Tente baixá-lo novamente ou abri-lo em outro app de PDF.

## Um documento na nuvem não abre

Verifique sua conexão e se o arquivo é baixado no Finder, depois tente novamente.

## O Agent não está disponível ou mostra somente trechos

O Agent requer o macOS 26 ou posterior, e a redação de respostas no dispositivo requer que o Apple Intelligence esteja ativado e pronto. Se a indexação falhar, clique em Retry na aba Ask About This Document. Consulte [Escolher como o Agent responde](agent-engines.md).

## Um modelo online não responde

Verifique a chave de API e o modelo em [Ajustes](settings.md), e se sua conta no serviço tem crédito. O VectorPDF responde no dispositivo se o serviço falhar.

## Minhas alterações desapareceram

As alterações precisam ser [salvas](save.md). Se outro app tiver alterado o arquivo enquanto você tinha alterações não salvas, escolher Reload from Disk as descarta.

## A ajuda não mostra este manual

O Tips só pode mostrar este manual quando o VectorPDF está na pasta Aplicativos. Mova-o para lá e escolha Help > VectorPDF Help novamente.

## Obter mais ajuda

Relate um problema ou faça uma pergunta no [GitHub](https://github.com/tomderham/vectorpdf/issues). Um PDF de exemplo ajuda, se você puder compartilhá-lo.

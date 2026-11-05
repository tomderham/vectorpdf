<!-- keywords: privacidade, dados, rede, telemetria, análises, segurança, pesquisas recentes, privacy, data, network, telemetry, analytics, iCloud, security -->
<!-- source: 936fa61fbdbf -->

# Privacidade

O VectorPDF não tem contas, análises, telemetria nem relatórios de falhas. Seus documentos são processados no seu Mac, e nada deles é enviado ao desenvolvedor.

## O que usa a rede

- **Verificação de atualizações:** o VectorPDF consulta o GitHub para saber qual é a versão mais recente cerca de uma vez por dia ou quando você escolhe Check for Updates. A solicitação não contém informações sobre você nem sobre seus documentos. Você pode desativar isso em [Ajustes](settings.md).
- **O Agent:** nada sai do seu Mac com o mecanismo On-Device. O [Private Cloud Compute e os modelos online](agent-engines.md) enviam sua pergunta e trechos do documento, e somente quando você faz uma pergunta. A configuração de um modelo online também usa sua chave para listar os modelos e enviar um pequeno teste.
- **iCloud:** seu estado de leitura é mantido na sua própria conta do iCloud: onde o arquivo está, a última página e o zoom, além dos nomes, excertos e páginas das suas âncoras. Os documentos, seu texto completo e as miniaturas das âncoras não são enviados. Suas pesquisas recentes também ficam lá.
- **Os links em que você clica** são abertos no navegador.
- **Serviços da Apple:** tradução, Look Up, fala e OCR são fornecidos pelo macOS e podem baixar arquivos de idioma da Apple. O Handoff compartilha com seus outros dispositivos o documento e a página que você está lendo.

## O que fica armazenado no seu Mac

O VectorPDF armazena suas preferências, favoritos, Grupos de Abas, posições de leitura, âncoras e carimbo. Ele também mantém um índice dos documentos que você usou com o Agent, miniaturas das âncoras e cópias de trabalho temporárias de documentos com edições de páginas ou tarjamentos não salvos, que são apagadas quando deixam de ser necessárias.

Ele também guarda as pesquisas recentes de cada documento. Para ver quanto espaço tudo isso ocupa, ou para limpá-lo, use Storage em [Settings](settings.md#free-up-space-or-remove-data).

As chaves de API de modelos online são armazenadas no seu chaveiro de início de sessão.

Para ver todos os detalhes, consulte a [política de privacidade no GitHub](https://github.com/tomderham/vectorpdf/blob/main/PRIVACY.md).

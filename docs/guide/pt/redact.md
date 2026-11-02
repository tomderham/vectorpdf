<!-- keywords: tarjar, tarja, tarjamento, ocultar, censurar, remover, confidencial, CPF, cartão de crédito, e-mail, telefone, data, localizar e tarjar, redact, redaction, redactions, remove, black out, sensitive, SSN, credit card, email, phone, date, find and redact, PDF -->
<!-- source: 90945f068642 -->

# Tarjar conteúdo confidencial

O tarjamento remove conteúdo de um PDF permanentemente. O VectorPDF apaga do arquivo o texto, os pixels de imagem e os traços que estão sob a área tarjada, junto com as anotações e os campos de formulário que a tocam. Ele não apenas os cobre com uma caixa, e as revisões anteriores não são mantidas quando você salva.

> **Aviso:** O tarjamento entra em vigor assim que você o aplica, e não há como desfazê-lo com Undo. O arquivo original só é alterado quando você salva, portanto, para recomeçar, feche o documento sem salvar. Guarde uma cópia do original e use Save As para salvar a versão tarjada com um novo nome.

Pressione ⌥⌘R ou escolha View > Show Redact Toolbar.

## Tarjar uma área

1. Escolha **Redact Region**.
2. Escolha Black ou White como cor da tarja.
3. Arraste sobre a área que deseja tarjar.

## Localizar e tarjar

1. Escolha **Find & Redact**.
2. Escolha o que procurar:
   - **Text / Phrase**, com as opções Match Case e Whole Word.
   - **Custom Regular Expression**, como `[A-Z]{3}-\d{5}`.
   - **Social Security Number (SSN)**, **Credit Card Number**, **Email Address**, **Phone Number** ou **Date**. Essas opções encontram automaticamente formatos comuns.
3. Clique em Find.
4. Verifique as correspondências. Clique em uma para vê-la na página e desmarque as que deseja manter.
5. Escolha uma ação:
   - **Redact** remove o conteúdo e deixa uma caixa preta ou branca.
   - **Remove** remove o conteúdo e não deixa nenhuma caixa.
6. Clique em **Redact Selected** ou **Remove Selected**.

> **Aviso:** A detecção automática pode deixar passar alguns itens, principalmente formatos incomuns ou texto em imagens. Verifique o documento antes de compartilhá-lo. O texto em páginas digitalizadas precisa ser tarjado com Redact Region.

## Salvar o resultado

Pressione ⇧⌘S para salvar o documento tarjado com um novo nome. Salvar também apaga o índice de busca do [Agent](agent.md) para o documento, que poderia conter o texto removido.

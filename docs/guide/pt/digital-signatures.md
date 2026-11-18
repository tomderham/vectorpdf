<!-- keywords: assinatura digital, assinaturas digitais, assinar, assinar com certificado, certificado, porta-chaves, assinado, signatário, certificado, certificação, válida, inválida, verificar, validar, confiança, identidade, carimbo de data/hora, adulterado, alterado, digital signature, digital signatures, sign, signing, sign with certificate, p12, pfx, keychain, signed, signer, certificate, certified, certification, valid, invalid, verify, validate, trust, identity, timestamp, PKCS, CAdES, PAdES, tampered, changed -->
<!-- source: 3d32c92200ad -->

# Assinar e verificar assinaturas digitais

Uma assinatura digital mostra quem assinou um documento e que ele não mudou desde então. Você pode [assinar um PDF](#sign) com um certificado próprio. Quando você abre um PDF assinado, o VectorPDF verifica as assinaturas e mostra o que encontrou em uma barra acima da página:

- **A assinatura é válida:** o documento não mudou desde que foi assinado, e o certificado do signatário foi emitido por uma autoridade em que o seu Mac confia.
- **A identidade do signatário não está verificada neste Mac:** o documento não mudou, mas nada garante quem o assinou. Consulte [Por que a identidade de um signatário pode não estar verificada](#signer-identity).
- **Inválida:** o documento foi alterado depois de assinado, ou a assinatura não corresponde a ele.

Clique em **Signature Details** para ver cada assinatura na aba Document da barra lateral. Para ocultar a barra, clique no botão de fechar dela.

> **Nota:** Um [carimbo](stamps.md) é uma imagem de uma assinatura, não uma assinatura digital.

## Assinar com um certificado {#sign}

Para assinar, você precisa de um certificado de assinatura com a chave privada dele. Sua organização ou uma autoridade certificadora pode lhe fornecer um, geralmente como um arquivo .p12 ou .pfx com uma senha. Os certificados do seu porta-chaves podem ser usados diretamente.

1. Escolha Edit > Sign with Certificate e clique no lugar da página onde a assinatura deve ficar. Pressione Esc para parar. Se o documento tiver um campo de assinatura vazio, você pode clicar no campo e escolher Sign with Certificate.
2. Escolha seu certificado. Para usar um arquivo, clique em **Choose Certificate File** e digite a senha dele. O arquivo é lido só para esta assinatura e não é adicionado ao seu porta-chaves.
3. Se quiser, digite um motivo (como “Aprovo este documento”) e o lugar onde você está assinando. Se você criou um [carimbo](stamps.md), pode mostrar sua assinatura à mão no campo. Caso contrário, seu nome é mostrado.
4. Clique em **Sign**.

Assinar salva o documento, então, se ele tiver alterações não salvas, o VectorPDF pergunta primeiro se você quer salvá-las. Elas passam a fazer parte do que você assina. O macOS pode pedir que você permita ao VectorPDF usar a chave do seu certificado.

A assinatura deixa os outros campos de formulário do documento como estavam, para que outras pessoas ainda possam preenchê-los, assinar também ou adicionar anotações sem invalidar a sua assinatura. Cada assinatura posterior é adicionada depois das anteriores da mesma forma.

A assinatura é uma assinatura PKCS #7 com SHA-256 que contém seu certificado e os das autoridades que o emitiram. Ela registra a hora do seu Mac. Ainda não tem um carimbo de data/hora de uma autoridade de carimbo do tempo.

## O que o VectorPDF verifica

Para cada assinatura, a lista na aba Document mostra:

- Se as partes do arquivo que ela assinou estão exatamente como foram assinadas.
- Se o arquivo foi salvo de novo depois de assinado, e se essas alterações estão entre as que a assinatura permite. Preencher campos de formulário, adicionar assinaturas e adicionar ou alterar anotações costuma ser permitido. Uma assinatura de certificação pode permitir menos alterações. Se foram adicionadas anotações depois da assinatura, a lista avisa: uma anotação pode cobrir o que foi assinado.
- Quem a assinou, pelo nome no certificado, e quem emitiu o certificado. O nome que o software de assinatura escreveu no documento também é mostrado quando é diferente.
- Quando foi assinada. Uma hora vinda de uma autoridade de carimbo do tempo é garantida. Uma hora vinda do próprio computador do signatário não é.
- O motivo e o lugar que o signatário informou, se houver.

Clique em uma assinatura para ir até ela na página. Para ver os certificados dela, clique em **Show Certificate**, ou clique nela com o botão direito e escolha Show Certificate.

O VectorPDF verifica o arquivo como foi salvo pela última vez, então as alterações não salvas não são incluídas. Ele verifica de novo toda vez que você salva.

## Por que a identidade de um signatário pode não estar verificada {#signer-identity}

Qualquer pessoa pode criar um certificado com qualquer nome. Uma assinatura só prova quem assinou se o certificado foi emitido por uma autoridade que verificou a identidade dessa pessoa, e o seu Mac confia nessa autoridade. O VectorPDF usa os certificados em que o seu Mac confia, no Acesso às Chaves.

Muitos PDFs assinados usam certificados de autoridades em que o Adobe Acrobat confia, mas o macOS não, então o VectorPDF informa que os signatários deles não estão verificados. Mesmo assim, o documento pode não ter mudado desde que foi assinado. Para confiar em uma autoridade, adicione o certificado dela ao Acesso às Chaves e defina-o como “Sempre Confiar”, mas só se tiver certeza de que é o verdadeiro.

O VectorPDF não se conecta à internet para verificar se um certificado foi revogado. Assim, ninguém fica sabendo que você abriu o documento.

## Salvar um documento assinado

Quando você salva um documento assinado, o VectorPDF adiciona suas alterações depois da parte assinada do arquivo e deixa essa parte como estava, para que as assinaturas continuem válidas na medida em que as alterações forem permitidas. Remover conteúdo com a [tarja](redact.md) reescreve o arquivo inteiro, então as assinaturas do documento deixam de ser válidas.

## Tipos de assinatura verificados

O VectorPDF verifica as assinaturas de PDF mais comuns: assinaturas PKCS #7 e CAdES (PAdES). Ele ainda não verifica carimbos de data/hora de documento nem assinaturas X.509 RSA antigas. Elas aparecem como **Not checked**.

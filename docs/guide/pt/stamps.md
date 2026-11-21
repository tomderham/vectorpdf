<!-- keywords: assinatura à mão, assinatura, assinar, carimbo, carimbos, assinaturas, iniciais, stamp, stamps, signature, signatures, sign, signing, initials, PDF, handwritten signature, digital signature, sign with certificate, certificate, p12, pfx, keychain, timestamp, certify, lock fields, which signature -->
<!-- source: 132d42959c5b -->

# Assinar um documento

Há duas formas de assinar, e elas fazem coisas diferentes. As duas estão no botão Sign, a assinatura na barra de ferramentas Markup (⇧⌘A).

| | Assinatura à mão | Assinatura digital |
| --- | --- | --- |
| O que é | Uma imagem da sua assinatura ou iniciais na página | Uma assinatura feita com seu certificado e guardada no arquivo |
| Mostra quem assinou | Não: qualquer um pode colar uma imagem | Sim, quando o certificado vem de uma autoridade em que o leitor confia |
| Mostra que o documento não mudou desde então | Não | Sim |
| Do que você precisa | Nada: desenhe, digite ou escolha uma imagem | Um certificado para assinar, da sua organização ou de uma autoridade certificadora |
| Pode ser retirada depois | Sim, como uma anotação | Só voltando a uma cópia salva antes de assinar |

Uma assinatura à mão basta quando uma imagem é suficiente, como em um formulário informal. Use uma assinatura digital para contratos, aprovações e tudo o que alguém possa precisar verificar depois. Uma assinatura digital também pode mostrar sua assinatura à mão no retângulo dela.

## Adicionar sua assinatura à mão {#add-your-handwritten-signature}

1. Mostre a barra de ferramentas Markup (⇧⌘A), clique no botão Sign e escolha Add Handwritten Signature. Na primeira vez, o VectorPDF pede que você crie sua assinatura:
   - **Draw:** assine com o trackpad ou o mouse.
   - **Type:** digite seu nome ou iniciais e escolha uma fonte.
   - **Image:** escolha um arquivo PNG ou JPEG. Se você escolher **Transparent background**, a página aparecerá através do fundo da imagem.
2. Clique onde quiser colocá-la.

Depois, arraste-a para movê-la ou arraste um canto para redimensioná-la. Para removê-la, selecione-a e pressione Delete, ou clique nela com o botão direito e escolha Delete Signature.

O VectorPDF guarda sua assinatura neste Mac para a próxima vez. Para alterá-la ou apagá-la, escolha VectorPDF > Settings, clique em General e use os botões ao lado de Handwritten Signature.

## Assinar com um certificado {#sign}

Para assinar, você precisa de um certificado de assinatura com a chave privada dele. Sua organização ou uma autoridade certificadora pode lhe fornecer um, geralmente como um arquivo .p12 ou .pfx com uma senha. Os certificados do seu porta-chaves podem ser usados diretamente.

1. Clique no botão Sign na barra de ferramentas Markup e escolha Sign with Certificate, ou escolha Edit > Sign with Certificate. Depois arraste um retângulo na página onde a assinatura deve ficar, ou clique para um do tamanho habitual. Pressione Esc para parar. Se o documento tiver um campo de assinatura vazio, você pode clicar no campo e escolher Sign with Certificate.
2. Escolha seu certificado. Uma prévia mostra como a assinatura vai ficar. Para usar um arquivo, clique em **Choose Certificate File** e digite a senha dele. O arquivo é lido só para esta assinatura e não é adicionado ao seu porta-chaves.
3. Se quiser, digite um motivo (como “Aprovo este documento”) e onde está assinando. Se você criou uma [assinatura à mão](#add-your-handwritten-signature), pode mostrá-la no campo. Caso contrário, seu nome é mostrado.
4. Se quiser, escolha em After Signing:
   - **Certify**, se ninguém assinou o documento ainda: diga quais alterações o mantêm válido daqui em diante: preencher formulários, assinar e adicionar anotações; preencher formulários e assinar; ou nenhuma. Um documento certificado aparece como certificado para todos que o verificam, e alterações posteriores que ele não permite invalidam sua assinatura.
   - **Lock form fields**, em um formulário: todos os campos, ou os que você escolher, ficam somente leitura e mantêm os valores que você assinou.
5. Clique em **Sign** e escolha onde salvar o documento assinado. O VectorPDF sugere uma cópia ao lado do original, com “(signed)” no fim do nome, e deixa o original sem assinatura; a cópia assinada então abre no lugar dele. Para assinar o próprio original, escolha-o em vez da cópia e clique em **Replace**.

Uma assinatura é feita sobre o documento como ele está salvo, então assinar sempre salva. Se o documento tiver alterações não salvas, o VectorPDF pergunta primeiro se você quer salvá-las; elas passam a fazer parte do que você assina. O macOS pode pedir que você permita ao VectorPDF usar a chave do seu certificado.

Uma assinatura não pode ser retirada de um arquivo assinado: ela existe para que qualquer pessoa saiba que o documento não mudou desde então. Assinar uma cópia mantém o original sem assinatura, para assinar de novo ou alterar.

A menos que você os bloqueie ou certifique o documento para menos, a assinatura deixa os outros campos de formulário do documento como estavam, para que outras pessoas ainda possam preenchê-los, assinar também ou adicionar anotações sem invalidar a sua assinatura. Cada assinatura posterior é adicionada depois das anteriores da mesma forma.

A assinatura é uma assinatura PKCS #7 com SHA-256 que contém seu certificado e os das autoridades que o emitiram. Ela registra a hora do seu Mac.

Para que um servidor de carimbo do tempo garanta quando você assinou, ative **Add a timestamp** e informe o endereço dele (sua organização pode ter um; há gratuitos, como o da DigiCert, `http://timestamp.digicert.com`). Com um carimbo de data/hora, sua assinatura pode ser verificada como era quando você assinou, mesmo depois que seu certificado expirar. O servidor recebe só uma impressão digital da assinatura, nada do documento. Um endereço que começa com `http://` funciona com os servidores públicos de carimbo do tempo conhecidos (como os da DigiCert, Sectigo, GlobalSign, Entrust e Apple) e com servidores da sua rede local; para qualquer outro servidor, use o endereço `https://` dele. Se o servidor não puder ser alcançado, nada é assinado e o documento fica como estava.

Para verificar as assinaturas de um documento, consulte [Verificar assinaturas digitais](digital-signatures.md).

## Assinar um formulário

Se um formulário tiver um campo de assinatura, clique em **Sign** no campo e escolha Add Handwritten Signature ou Sign with Certificate. Consulte [Preencher formulários](forms.md).

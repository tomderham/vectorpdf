<!-- keywords: aba Document, campos de formulário, campos, assinaturas, assinado, assinatura digital, certificado, links, hiperlinks, URLs, links da web, destinos nomeados, destinos, conteúdo, barra lateral, document tab, form fields, fields, signatures, signed, digital signature, certified, hyperlinks, web links, named destinations, destinations, contents, sidebar -->
<!-- source: 83fd92f682a7 -->

# Campos de formulário, assinaturas, links e destinos

A aba Document (uma caixa), na parte superior da barra lateral, lista o que um documento contém além das páginas. Escolha o que ela mostra no menu na parte superior da aba:

- **Layers:** consulte [Mostrar e ocultar camadas](layers.md).
- **Attachments:** consulte [Arquivos anexados a um PDF](attachments.md).
- **Signatures:** as assinaturas digitais do documento e se cada uma é válida. Consulte [Assinar e verificar assinaturas digitais](digital-signatures.md).
- **Form Fields:** cada campo de um formulário, com seu valor, incluindo os campos de assinatura.
- **Links:** cada link, com o texto em que está e para onde leva.
- **Destinations:** os lugares nomeados do documento para onde os links podem apontar.

Signatures é listado sempre que um documento está assinado. Form Fields, Links e Destinations só são listados quando você ativa **List form fields, links and destinations in the sidebar** em VectorPDF > Settings > General. A maioria dos documentos tem links, então, caso contrário, a aba apareceria em quase todos.

O menu oferece apenas o que o documento tem, e a aba só aparece quando ele tem pelo menos um deles.

## Campos de formulário e assinaturas

Os campos são listados página por página, pelo nome que o formulário dá a eles. Cada um mostra seu valor e **Required** quando o formulário diz que ele precisa ser preenchido. Mantenha o cursor sobre um campo para ver seu nome completo e seu tipo. Clique em um campo para ir até ele na página; ele fica destacado por um instante. Para preencher campos, consulte [Preencher formulários](forms.md). A lista mostra os novos valores enquanto você digita.

Um campo de assinatura mostra quem o assinou e se a assinatura é válida, ou **Not signed**. Para saber mais sobre cada assinatura, escolha Signatures no menu na parte superior da aba. Consulte [Assinar e verificar assinaturas digitais](digital-signatures.md).

## Links

Os links são listados página por página assim que cada página é lida, então os primeiros links de um documento longo aparecem logo. Use os botões acima da lista para mostrar **All** os links, só os **Web** ou os **In Document**, e digite em **Filter** para encontrar um link pelo texto ou pelo endereço.

| Para | Faça isto |
| --- | --- |
| Mostrar um link na página dele | Clique nele |
| Seguir um link | Clique duas vezes nele. Um link da web abre no seu navegador. |
| Copiar um endereço da web | Clique com o botão direito no link e escolha Copy Address |

## Destinos

Destinos são lugares nomeados de um documento, como `section.2` ou `figure.3`. O LaTeX e outros programas os criam para que os links apontem para eles. Clique em um destino para ir até ele. Para copiar o nome, clique nele com o botão direito e escolha Copy Name.

<!-- keywords: editar sumário, adicionar marcador, sumário a partir dos títulos, títulos, criar índice, renomear, recuar, sumário, índice, conteúdo, marcadores, miniatura, miniaturas, barra lateral, outline, table of contents, TOC, contents, bookmarks, thumbnail, thumbnails, sidebar, bookmark, add bookmark, edit outline, build outline, headings, generate table of contents, rename, indent, outdent -->
<!-- source: 4dd1a582a981 -->

# Sumário e miniaturas

Clique na aba Outline & Thumbnails na parte superior da barra lateral e escolha **Outline** ou **Thumbnails**.

## Sumário

O sumário (Outline) é o índice do documento, se ele tiver um. A seção que você está lendo fica realçada conforme você rola.

- **Ir para uma seção:** clique nela. O título dela é rolado para perto do topo da janela, ou fica onde está se você já consegue vê-lo.
- **Mostrar ou ocultar subseções:** clique na seta ao lado de uma seção.
- **Encontrar uma seção:** digite no campo “Search outline”. Somente as seções correspondentes são mostradas.
- **Manter uma seção à mão:** clique nela com o botão direito para criar uma [âncora](anchors.md) ou abri-la em uma nova janela.

## Editar o sumário {#edit-the-outline}

Você pode adicionar entradas ao sumário de um documento (outros apps podem chamá-las de marcadores), e renomeá-las, movê-las e apagá-las. As alterações passam a fazer parte do arquivo quando você [salva](save.md).

Para adicionar uma entrada, vá ao lugar a que ela deve levar e escolha Edit > Add Outline Entry (⌥⌘B). Se você selecionou texto, a entrada leva a esse texto, que é sugerido como título. Caso contrário, ela leva ao topo da página que você está lendo. Digite um título e clique em **Add**. As entradas adicionadas dessa forma entram entre as entradas de nível superior na ordem das páginas, então essa também é a forma de começar um sumário em um documento que não tem nenhum.

Para todo o resto, clique com o botão direito em uma entrada:

| Para | Escolha |
| --- | --- |
| Adicionar uma entrada depois desta ou dentro dela | Add Entry After ou Add Entry Inside |
| Renomeá-la | Rename |
| Fazê-la levar ao texto selecionado ou à página que você está lendo | Go Here Instead |
| Movê-la entre as entradas do seu nível | Move Up ou Move Down |
| Colocá-la dentro da entrada acima ou tirá-la da entrada em que está | Indent ou Outdent |
| Apagá-la, com as entradas que estão dentro dela | Delete Entry |

Você também pode arrastar uma entrada para movê-la, ou soltá-la sobre outra entrada para colocá-la dentro. As entradas dentro dela se movem junto. Enquanto o sumário está filtrado pelo campo “Search outline”, as entradas não podem ser editadas. Edit > Undo (⌘Z) desfaz as alterações no sumário, uma de cada vez.

### Criar um sumário a partir dos títulos

Escolha Edit > Build Outline from Headings para criar em uma só etapa um sumário com os títulos do documento. O comando também está no menu de contexto de uma entrada do sumário. Se o documento já tem um sumário, você é perguntado antes de ele ser substituído; Edit > Undo o traz de volta.

Em um PDF com tags, os títulos são os marcados pelas tags. Em outros PDFs, o VectorPDF procura linhas que se destacam do texto: maiores, ou em negrito onde o texto não está. Um estilo maior é um nível mais alto que um menor, e números de seção como 3.2.1 dão os níveis dentro de um mesmo estilo. Cabeçalhos e rodapés repetidos, legendas de figuras e tabelas e as linhas de um índice são deixados de fora.

Confira o resultado: os estilos de um documento nem sempre dizem quais linhas são títulos. Renomeie, mova ou apague entradas como descrito acima. Títulos em páginas digitalizadas não são encontrados, mesmo depois que o texto delas é reconhecido.

## Miniaturas

As miniaturas (Thumbnails) mostram todas as páginas. Clique em uma para ir até aquela página.

Mantenha ⌘ pressionada para selecionar várias páginas, ou ⇧ para selecionar um intervalo. Depois, arraste-as para uma nova posição ou clique com o botão direito para girá-las, duplicá-las, extraí-las ou apagá-las. Consulte [Reorganizar páginas](pages.md).

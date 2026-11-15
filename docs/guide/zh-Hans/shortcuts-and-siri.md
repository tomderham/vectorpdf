<!-- keywords: 快捷指令, Siri, Spotlight, 自动化, 操作, 提问, 搜索, 提取页面, 打开文稿, 工作流程, Shortcuts, automation, action, actions, App Intents, ask, search, extract pages, open document, workflow -->
<!-- source: 0598b760c342 -->

# 通过快捷指令和 Siri 使用 VectorPDF

VectorPDF 会向“快捷指令” App 添加操作，因此你可以在自己的快捷指令中使用它们，也可以通过 Spotlight 和 Siri 使用。

| 操作 | 功能 |
| --- | --- |
| Ask About Document | 向 [Agent](agent.md) 提问，并返回附有页码引用的回答 |
| Search Document | 像搜索栏一样查找文本，并返回每个匹配项及其页码 |
| Extract Pages | 用 PDF 中的部分页面（如 `1-3, 5`）创建新的 PDF |
| Open Document | 在 VectorPDF 中打开文稿；如果你指定了页面，则打开到该页 |

如果你没有为 Ask、Search 或 Extract Pages 选择文稿，操作会使用 VectorPDF 中最前面的文稿。

## 在快捷指令中使用操作

1. 打开“快捷指令” App，然后创建或打开一个快捷指令。
2. 在操作列表中搜索 VectorPDF，然后将操作拖到你的快捷指令中。
3. 填写操作。若要使用快捷指令中前面步骤的文件（例如获取文件的操作得到的文件），请点按 Document 并选择该文件。

每个操作都会传递它返回的内容：回答、匹配项列表或新的 PDF。然后你可以将其发送给另一个操作，例如创建 PDF、添加到备忘录或发送信息的操作。

如果没有出现 VectorPDF 的操作，请打开 VectorPDF 一次，然后退出并重新打开“快捷指令”。

## 让 Siri 来做

你可以对 Siri 说出或输入这些短语。Siri 会询问它还需要的内容，例如你的问题。由于 VectorPDF 尚未翻译，这些短语为英文，因此在 Siri 的语言为英文时可用：

- "Ask VectorPDF about this document"
- "Search this document in VectorPDF"
- "Extract pages in VectorPDF"
- "Open a document in VectorPDF"

你也可以在 Spotlight 中输入操作名称来找到它们。

## 关于各个操作

- **Ask About Document** 会在文稿尚未打开时，在你正在使用的窗口后面用 VectorPDF 打开文稿。问题和回答也会显示在文稿的 Ask About This Document 标签页中，你可以在那里阅读来源并继续提问。它需要打开 Agent，并使用你在[选择 Agent 的回答方式](agent-engines.md)中选择的引擎来回答。如果无法生成回答，它会返回最匹配的段落。
- **Search Document** 使用 Smart Search 和你的 [Ignored Search Patterns](search.md#ignore-clutter-in-the-text)，如果你打开了 Match Case 和 Whole Words，也会使用它们。它最多返回 100 个匹配项，并告诉你总共有多少个。对于已打开的文稿，它按其在 VectorPDF 中的状态搜索，包括未存储的更改，且只搜索显示的图层；其他文稿则无需打开即可搜索。
- **Extract Pages** 接受以逗号分隔的页面和范围。像 `5-` 这样的范围会一直到最后一页，`3-1` 则按倒序给出页面。它读取文件上次存储时的内容，并且不会更改文件。新 PDF 以文稿和页面命名，例如“Report (Pages 1-3, 5).pdf”。
- **Open Document** 会在文稿已打开时将其标签页置于最前面。

受密码保护的文稿必须先在 VectorPDF 中打开并输入密码，Search Document 才能搜索它。Extract Pages 无法使用受密码保护的文稿。

> **注：** 操作返回的内容会发送到快捷指令或 Siri，再从那里发送到快捷指令的下一步。Ask About Document 只发送你在 VectorPDF 中提问时 Agent 会发送的内容。请参阅[隐私](privacy.md)。

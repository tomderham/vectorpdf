<!-- keywords: 涂黑, 修订, 遮盖, 移除, 敏感, 脱敏, 社会安全号码, 信用卡, 电子邮件, 电话, 日期, 查找并涂黑, 元数据, 书签, 附件, redact, redaction, redactions, remove, black out, sensitive, SSN, credit card, email, phone, date, find and redact, metadata, bookmarks, attachments, PDF -->
<!-- source: d8be777cd6d7 -->

# 涂黑敏感内容

涂黑操作会从 PDF 中永久移除内容。VectorPDF 会从文件中删除涂黑区域下方的文本、图像像素和线条图，以及与该区域接触的所有注释和表单栏位。它不只是用方框遮盖这些内容，存储时也不会保留之前的修订版本。

首次在文稿中进行涂黑时，会有提醒说明还有哪些内容会更改：

- **从整个文稿中移除：** 标题和作者等元数据、附件、页面缩略图、用于辅助功能的替代文本，以及 XFA 表单数据。若要保留这些内容，请涂黑副本。
- **书签会保留，** 其标题中每个被涂黑的单词都会替换为 [Redacted]。图像和扫描件中的文本无法匹配，因此涂黑这些内容后请自行检查书签。
- **不会移除：** 命名目标、页面标签、图层名称和 JavaScript。这些内容中可能仍含有该文本。

> **警告：** 涂黑操作一经应用就会立即生效，并且没有 Undo。在你存储之前，原始文件不会更改，因此若要重新开始，请关闭文稿且不存储。请保留原始文件的副本，并使用 Save As 以新名称存储涂黑后的版本。

按下 ⌥⌘R，或者选取 View > Show Redact Toolbar。

## 涂黑区域

1. 选取 **Redact Region**。
2. 选取 Black 或 White 作为涂黑颜色。
3. 拖移划过要涂黑的区域。

## 查找并涂黑

1. 选取 **Find & Redact**。
2. 选取要查找的内容：
   - **Text / Phrase**，可使用 Match Case 和 Whole Word 选项。
   - **Custom Regular Expression**，例如 `[A-Z]{3}-\d{5}`。
   - **Social Security Number (SSN)**、**Credit Card Number**、**Email Address**、**Phone Number** 或 **Date**。这些选项会自动查找常见格式。
3. 点按 Find。
4. 检查匹配项。点按某一项可在其所在页面上查看，并取消选择你想保留的项。
5. 选取一个操作：
   - **Redact** 移除内容并留下黑色或白色方框。
   - **Remove** 移除内容且不留下方框。
6. 点按 **Redact Selected** 或 **Remove Selected**。

> **警告：** 自动检测可能会遗漏内容，特别是不常见的格式或图像中的文本。共享文稿前请检查。扫描页面上的文本需要使用 Redact Region 来涂黑。

## 存储结果

按下 ⇧⌘S 以新名称存储涂黑后的文稿。存储时还会删除文稿的 [Agent](agent.md) 搜索索引，因为其中可能包含已移除的文本。

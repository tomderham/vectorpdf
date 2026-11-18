<!-- keywords: Document 标签页, 表单栏位, 栏位, 签名, 已签名, 数字签名, 认证, 链接, 超链接, URL, 网页链接, 命名目标, 目标, 内容, 边栏, document tab, form fields, fields, signatures, signed, digital signature, certified, links, hyperlinks, web links, named destinations, destinations, contents, sidebar, URLs -->
<!-- source: 83fd92f682a7 -->

# 表单栏位、签名、链接和目标

边栏顶部的 Document 标签页（一个盒子）会列出文稿除页面之外包含的内容。从标签页顶部的菜单中选择它显示的内容：

- **Layers：**请参阅[显示和隐藏图层](layers.md)。
- **Attachments：**请参阅[附加到 PDF 的文件](attachments.md)。
- **Signatures：**文稿的数字签名，以及每个签名是否有效。请参阅[进行数字签名和检查数字签名](digital-signatures.md)。
- **Form Fields：**表单中的每个栏位及其值，包括签名栏位。
- **Links：**每个链接，以及它所在的文本和指向的位置。
- **Destinations：**文稿中可供链接指向的命名位置。

只要文稿已签名，就会列出 Signatures。只有在 VectorPDF > Settings > General 中打开 **List form fields, links and destinations in the sidebar** 后，才会列出 Form Fields、Links 和 Destinations。大多数文稿都带有链接，否则几乎每份文稿都会出现这个标签页。

菜单只提供文稿中有的内容，而且只有当文稿至少包含其中一种时，这个标签页才会出现。

## 表单栏位和签名

栏位按页面列出，使用表单为其指定的名称。每个栏位都会显示其值；如果表单要求必须填写，还会显示 **Required**。将指针悬停在栏位上可查看其完整名称和类型。点按栏位可前往页面上的该栏位，它会短暂显示外框。若要填写栏位，请参阅[填写表单](forms.md)。你键入时，列表会显示新值。

签名栏位会显示签名人以及签名是否有效，或者显示 **Not signed**。若要进一步了解每个签名，请从标签页顶部的菜单中选取 Signatures。请参阅[进行数字签名和检查数字签名](digital-signatures.md)。

## 链接

每读完一页就会按页面列出其中的链接，因此长文稿的第一批链接会立即出现。使用列表上方的按钮可显示 **All** 链接、仅显示 **Web** 链接或 **In Document** 链接；在 **Filter** 中键入可按文本或地址查找链接。

| 若要 | 请这样做 |
| --- | --- |
| 在页面上显示链接 | 点按链接 |
| 打开链接 | 连按链接。网页链接会在浏览器中打开。 |
| 拷贝网址 | 右键点按链接，然后选取 Copy Address |

## 目标

目标是文稿中的命名位置，例如 `section.2` 或 `figure.3`。LaTeX 和其他程序会创建目标，供链接指向。点按目标可前往该位置。若要拷贝其名称，请右键点按它，然后选取 Copy Name。

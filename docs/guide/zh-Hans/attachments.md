<!-- keywords: 附件, 附加文件, 嵌入文件, 回形针, 文件包, 电子发票, 存储附件, 提取, attachments, attachment, attached files, embedded files, paperclip, portfolio, e-invoice, electronic invoice, ZUGFeRD, Factur-X, XML, Quick Look, save attachment, extract -->
<!-- source: e084e93b9409 -->

# 附加到 PDF 的文件

PDF 可以在内部携带其他文件：报告附带的电子表格、图纸集附带的 CAD 模型，或者电子发票的数据。当文稿带有附件时，边栏顶部会出现 Attachments 标签页（一个回形针）。带有附件的一两页文稿打开时会显示 Attachments 标签页。

每个附件都会显示其名称，如果 PDF 中包含这些信息，还会显示其描述、大小以及附加到的页面。将指针悬停在附件上，可以查看文件类型和日期。

| 若要 | 请这样做 |
| --- | --- |
| 预览附件 | 连按附件，或者选中它后按空格键 |
| 预览下一个或上一个附件 | 在 Quick Look 打开时，按下箭头键或上箭头键 |
| 在其 App 中打开 | 右键点按附件，然后选取 Open |
| 存储副本 | 右键点按附件，然后选取 Save As…，或者将其拖到 Finder |
| 全部存储 | 点按标签页顶部的 Save All…，然后选取一个文件夹 |
| 前往其页面 | 右键点按附件，然后选取 Show on Page |

> **警告：** 附件可以是任何类型的文件，包括 App 或脚本。只打开你信任的文件。VectorPDF 会将它从 PDF 中取出的文件标记为已下载，因此 macOS 会在 App 和脚本运行前对其进行检查，就像对待来自网络的文件一样。

## 电子发票

ZUGFeRD 和 Factur-X 发票将其数据存放在一个 XML 文件中，该文件通常名为 `factur-x.xml` 或 `zugferd-invoice.xml`。它会与其他附件一同列出，因此你可以将其存储下来供会计软件使用。VectorPDF 本身不会显示发票的详细信息。

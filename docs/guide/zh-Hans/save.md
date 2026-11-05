<!-- keywords: 存储, 另存为, 未存储, 共享, 更改, 复原, 上次存储的版本, 重新载入, 放弃更改, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all -->
<!-- source: 2c2bdeb1617c -->

# 存储更改

在你存储之前，标记、表单输入内容、页面更改和涂黑操作都不会写入文件。有未存储更改的窗口，其关闭按钮中会显示一个圆点。

| 若要 | 请执行以下操作 |
| --- | --- |
| 存储 | 选取 File > Save，或者按下 ⌘S |
| 以新名称存储副本 | 选取 File > Save As，或者按下 ⇧⌘S |
| 存储受密码保护的副本 | 选取 File > [Save Encrypted with Password](passwords.md)，或者按下 ⌥⌘S |

如果你关闭有未存储更改的文稿，VectorPDF 会询问是否存储。

## 放弃更改

若要放弃上次存储以来所做的全部更改，请选取 File > Revert to Saved。VectorPDF 会先询问，然后按上次存储时的状态打开文件，并停留在你正在阅读的页面。此操作无法撤销。

若要制作文稿的较小副本，请参阅[Optimized PDF](export.md#optimized-pdf)。

## 共享文稿

选取 File > Share 可使用 macOS 共享服务，选取 File > Show in Finder (⇧⌘R) 可找到该文件。在 Start 屏幕上，右键点按文稿可在访达 (Finder) 中显示它。

## 哪些内容不会存储在 PDF 中

某些内容保留在 VectorPDF 中，不会随文件一起移动：[锚点](anchors.md)、你的[阅读位置](reading-positions.md)、视图旋转以及 [OCR](scanned-pages.md) 识别出的文本。

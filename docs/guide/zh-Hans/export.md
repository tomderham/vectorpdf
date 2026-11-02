<!-- keywords: 导出, 转换, 纯文本, 文本, Word, 拼合, 注释摘要, 表格, export, convert, plain text, text, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF -->
<!-- source: c72be921ec25 -->

# 导出为其他格式

若要导出整个文稿，请选取 File > Export Document As，然后选取 Plain Text、Word Document、Scalable Vector Graphics 或 Flattened PDF。注释摘要和测量结果有各自的命令。

## 纯文本（Plain Text）

将文稿的文本存储为 `.txt` 文件。

## Word 文稿（Word Document）

存储可在 Word 和其他应用中编辑的 `.docx` 文件。复杂的页面布局可能与 PDF 看起来不同。

## SVG

将每个页面存储为一个可缩放矢量图形文件，其中的文本转换为矢量路径，因此外观与 PDF 完全相同。多页文稿会存储为一个文件夹，每页一个文件。

## 拼合的 PDF（Flattened PDF） {#flattened-pdf}

存储一个 PDF，其中的注释和表单栏位已成为页面的一部分，因此无法更改。在存储对话框中，选取要拼合的内容：

- **Flatten annotations and markups**
- **Flatten form fields (make static)**

> **注：** 拼合不会移除下层的内容。若要移除内容，请使用[涂黑](redact.md)功能。

## 注释摘要

选取 File > Export Annotations Summary (⇧⌘E) 可存储文稿的注释列表，包括其他应用中的注释，以及它们的作者、状态和回复。默认情况下，它是一个 Markdown 文件。将文件扩展名设为 `.csv` 可改为存储电子表格。

## 测量结果

若要导出测量结果，请使用[工程量表](takeoff.md)。

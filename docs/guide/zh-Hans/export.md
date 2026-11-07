<!-- keywords: 导出, 转换, 纯文本, 文本, Word, 拼合, 注释摘要, 表格, 优化, 减小文件大小, 压缩, 更小, 图像, 字体, 轮廓, 文本转轮廓, 绘图仪, export, convert, plain text, text, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF, optimize, optimized, reduce file size, compress, smaller, downsample, images, fonts, subset, outlines, text to outlines, plotter -->
<!-- source: 6d68e3315dc3 -->

# 导出为其他格式

若要导出整个文稿，请选取 File > Export Document As，然后选取 Plain Text、Word Document、Scalable Vector Graphics、Flattened PDF 或 Optimized PDF。注释摘要和测量结果有各自的命令。

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

拼合的 PDF 只包含所显示[图层](layers.md)上的内容。隐藏的图层及其上的所有内容（包括注释）都会被排除。剩下的图层仍可显示和隐藏，拼合到页面上的注释仍留在各自的图层上。

> **注：** 拼合不会移除下层的内容。若要移除内容，请使用[涂黑](redact.md)功能。

## 优化的 PDF（Optimized PDF） {#optimized-pdf}

存储 PDF 的较小副本，其中包括你尚未存储的更改。打开的文稿不会更改。文稿不再使用的数据会被移除，重复项会被合并，所有内容都会被压缩。在存储对话框中，你还可以选取：

- **Keep only the characters each font uses:** 移除嵌入字体中文稿未使用的部分。默认打开。
- **Images:** 保持图像不变，或将其降低到 300 dpi（用于打印）或 150 dpi（用于在屏幕上阅读）。只有分辨率高于此值的图像才会被降低。照片存储为 JPEG；图表和截屏保持无损。黑白扫描件保持不变。
- **Convert text to outlines:** 将每个字母绘制为形状，使文稿在没有其字体的绘图仪、切割机和打印系统上看起来一样。副本中的文本无法被选择、搜索或拷贝。

副本能缩小多少取决于文稿。降低图像分辨率时，扫描件和照片缩小得最多。

## 注释摘要

选取 File > Export Annotations Summary (⇧⌘E) 可存储文稿的注释列表，包括其他应用中的注释，以及它们的作者、状态和回复。默认情况下，它是一个 Markdown 文件。将文件扩展名设为 `.csv` 可改为存储电子表格。

## 测量结果

若要导出测量结果，请使用[工程量表](takeoff.md)。

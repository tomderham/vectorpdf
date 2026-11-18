<!-- keywords: 页眉, 页脚, 页码, 页面编号, Bates, Bates 编号, 水印, 草稿, 机密, 法律, header, headers, footer, footers, page numbers, page numbering, Bates numbers, Bates numbering, watermark, watermarks, DRAFT, CONFIDENTIAL, stamp text, legal, discovery, PDF -->
<!-- source: 7e05ab7492d9 -->

# 页眉、页脚、Bates 编号和水印

你可以在页面的顶部和底部添加文本（例如标题、页码或 Bates 编号），并在页面上添加“草稿”或“机密”之类的水印。选取 Edit > Headers, Footers and Watermark，填写所需部分，然后点按 **Add**。

VectorPDF 会在文稿中保留你的选择，因此你之后可以更改或移除页眉、页脚和水印。再次选取 Edit > Headers, Footers and Watermark，进行更改，然后点按 **Update**。若要全部移除，请点按 **Remove All**。

存储文稿时，这些更改会成为文件的一部分。请参阅[存储](save.md)。

## 页眉和页脚

在六个框中的任意一个中输入：页眉和页脚各自的左侧、中间和右侧。不想放内容的地方，让框保持为空。

若要添加页码或其他随页面变化的值，请在框内点按，然后从 **Insert** 菜单中选取：

| Insert | 显示 |
| --- | --- |
| Page Number | 页面的编号，从第一个加标记的页面开始计数。请参阅[页面和编号](#pages-and-numbers)。 |
| Page Count | 文稿的页数 |
| Bates Number | 页面的 Bates 编号 |
| Date | 今天的日期 |
| File Name | 文稿的文件名 |

每一项都会以双尖括号括起的词显示在框中，例如 `<<page>>`。例如，输入 `第 `，插入 Page Number，输入 ` 页，共 `，插入 Page Count，再输入 ` 页`，即可得到“第 3 页，共 12 页”。

你可以选择文本的字体、大小和颜色，以及边距：页眉到页面顶部、页脚到页面底部以及两者到左右两侧的距离，以点为单位（72 点为 1 英寸）。

## 水印

输入水印文本。按下 Return 键可输入第二行。然后选取：

- **Font** 和 **Color**。
- **As large as fits the page**，或自定大小。
- **Opacity：**水印的明显程度。浅色水印能让页面保持易读。
- **Angle：**水平、对角或垂直。
- **Behind the page's content：**将水印绘制在页面的文本和图片下方，而不是上方。有背景的页面（例如扫描页面）会遮住其后面的水印。

## 页面和编号 {#pages-and-numbers}

- **Pages：**所有页面、奇数页或偶数页，以及从某一页到另一页。将 From 或 To 留空表示第一页或最后一页。
- **First page marked is page：**Page Number 为第一个加标记的页面指定的编号。每加标记一页，编号加一。
- **Bates numbers：**前缀（例如案件名或公司名）、位数、起始编号和后缀。每加标记一页，Bates 编号加一，并用零补齐位数，例如 ACME-000001。在页眉或页脚中插入 Bates Number 即可显示。

## 须知

- 页眉、页脚和水印是页面的一部分，而不是[注释](draw-and-notes.md)，因此会被打印，并在其他 App 中显示。它们被标记为页面装饰，屏幕阅读器可以跳过。你可以搜索和选择其中的文本。
- 边距按页面显示时的方向测量，因此在旋转过的页面上，页眉仍位于顶部。
- VectorPDF 只能更改或移除它自己添加的页眉、页脚和水印。其他 App 添加的属于页面内容的一部分。
- 将它们添加到[已数字签名](digital-signatures.md)的文稿会更改已签署的内容，因此其签名会失效。

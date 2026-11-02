<!-- keywords: 搜索, 查找, 查找下一个, 区分大小写, 全字匹配, 智能搜索, 忽略的模式, 正则表达式, 标签, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, PDF -->
<!-- source: 4bafc06135d7 -->

# 搜索文稿

## 查找文本

1. 按下 ⌘F。VectorPDF 会在边栏中显示 Search 标签页。
2. 键入要查找的内容。结果一经找到就会显示，并从你当前所在的页面开始。

每个结果都会显示所在页面及周围的文本，文稿中的每个匹配项都会高亮显示。

## 在结果之间移动

| 若要 | 请执行以下操作 |
| --- | --- |
| 前往下一个结果 | 按下 Return 键或 ⌘G，或者点按下箭头 |
| 前往上一个结果 | 按下 ⇧Return 或 ⇧⌘G，或者点按上箭头 |
| 前往任一结果 | 点按它 |
| 逐个浏览列表 | 点按一个结果，然后按下箭头键 |

右键点按结果可[从中创建锚点](anchors.md)，或者在新窗口中打开它。

## 搜索选项 {#search-options}

点按搜索栏旁边的选项按钮：

- **Match Case：** 仅查找大小写相同的文本。
- **Whole Word：** 不匹配较长单词中的部分内容。
- **Smart Search：** 除非你将其关闭，否则此选项处于打开状态。空格、连字符、破折号和换行符可以相互匹配，因此搜索“end-to-end”也会找到“end to end”，即使它跨越换行也是如此。直引号和弯引号也可以相互匹配。

## 忽略文本中的干扰内容 {#ignore-clutter-in-the-text}

有些文稿在句子中间放置标记（例如引文编号），导致无法找到短语。Smart Search 可以跳过这些标记。

1. 选取 VectorPDF > Settings。
2. 在 Ignored Search Patterns 旁边，点按 Edit。
3. 添加一个现成的模式或你自己的正则表达式，然后将其打开。

现成的模式涵盖 [12] 这样的数字引文、商标符号、*123 这样的星号页码以及 IEEE 802.11 注释标签。

## 扫描文稿

扫描页面在被识别之前没有可搜索的文本。请参阅[搜索和选择扫描页面上的文本](scanned-pages.md)。

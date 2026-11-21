<!-- keywords: 搜索, 查找, 查找下一个, 区分大小写, 全字匹配, 智能搜索, 忽略的模式, 正则表达式, 标签, 最近搜索, 搜索历史, 章节, 大纲, 目录, 右侧, 大纲旁边, 移动搜索, search, find, find next, match case, whole word, smart search, ignored patterns, regular expression, regex, tags, recent searches, search history, section, outline, table of contents, right side, beside the outline, move search, PDF -->
<!-- source: 9e3d931100aa -->

# 搜索文稿

## 查找文本

1. 按下 ⌘F。VectorPDF 会在边栏中显示 Search 标签页；如果你已将它[移到窗口右侧](#see-results-beside-the-outline)，则会显示在右侧。
2. 键入要查找的内容。结果一经找到就会显示，并从你当前所在的页面开始。

结果按页面列出，每个结果附有周围的文本，文稿中的每个匹配项都会高亮显示。在带有[大纲](outline-and-thumbnails.md)的文稿中，结果还会按所在章节分组。在你滚动浏览某个章节的结果时，章节名称会一直停留在列表顶部。要查看它属于哪些上级章节，请将指针悬停在名称上。

## 在结果之间移动

| 若要 | 请执行以下操作 |
| --- | --- |
| 前往下一个结果 | 按下 Return 键或 ⌘G，或者点按下箭头 |
| 前往上一个结果 | 按下 ⇧Return 或 ⇧⌘G，或者点按上箭头 |
| 前往任一结果 | 点按它 |
| 逐个浏览列表 | 点按一个结果，然后按下箭头键 |

右键点按结果可[从中创建锚点](anchors.md)，或者在新窗口中打开它。

## 在大纲旁边查看结果 {#see-results-beside-the-outline}

要同时查看结果和大纲，请点按搜索栏旁边的选项按钮，然后选取 Show Search on Right。Search 会移到窗口右侧，边栏则显示大纲；如果文稿没有大纲，则显示页面缩略图。每个有结果的大纲条目都会显示结果数量，包含当前结果的章节的数量会高亮显示。子章节处于隐藏状态的章节也会计入其中的结果。点按大纲条目后，页面会显示该章节的标题，结果列表会滚动到该章节的结果（如果该章节本身没有结果，则滚动到其子章节的结果）；在你点按某个结果之前，当前结果保持不变。

每个文稿都会记住你把 Search 放在哪一侧。要把它放回边栏，请再次选取 Show Search on Right 将其关闭。当它在右侧时，要隐藏它，请点按旁边的关闭按钮（×）。要再次显示它，请按下 ⌘F 或点按边栏顶部的 Search 按钮。

Search 与 [Inspector](rulers-and-inspector.md#the-inspector) 共用窗口右侧。两者都打开时，使用顶部的 Search 和 Inspector 按钮在它们之间切换。

## 再次搜索以前搜索过的内容

每个文稿会记住你前往过结果的最近 10 次搜索。要再次搜索其中一项：

- 点按搜索栏中的放大镜并选择它，或者
- 在搜索栏为空时，在搜索栏下方的 Recent Searches 列表中点按它。

VectorPDF 会前往最近的结果。要清除文稿的搜索记录，请从放大镜中选择 Clear Recent Searches，或点按列表上方的 Clear。对文稿应用涂黑也会清除其最近搜索。

## 搜索选项 {#search-options}

点按搜索栏旁边的选项按钮：

- **Match Case：** 仅查找大小写相同的文本。
- **Whole Word：** 不匹配较长单词中的部分内容。
- **Smart Search：** 除非你将其关闭，否则此选项处于打开状态。空格、连字符、破折号和换行符可以相互匹配，因此搜索“end-to-end”也会找到“end to end”，即使它跨越换行也是如此。直引号和弯引号也可以相互匹配。
- **Show Search on Right：** 将 Search 从边栏移到窗口右侧，以便你在[大纲旁边](#see-results-beside-the-outline)查看它。

## 忽略文本中的干扰内容 {#ignore-clutter-in-the-text}

有些文稿在句子中间放置标记（例如引文编号），导致无法找到短语。Smart Search 可以跳过这些标记。

1. 选取 VectorPDF > Settings，然后点按 Advanced。
2. 在 Ignored Search Patterns 旁边，点按 Edit。
3. 添加一个现成的模式或你自己的正则表达式，然后将其打开。

现成的模式涵盖 [12] 这样的数字引文、商标符号、*123 这样的星号页码以及 IEEE 802.11 注释标签。

## 扫描文稿

扫描页面在被识别之前没有可搜索的文本。请参阅[搜索和选择扫描页面上的文本](scanned-pages.md)。

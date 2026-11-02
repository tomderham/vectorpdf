<!-- keywords: 引用, 交叉引用, 其他文稿, 其他标签页, 章节, 条款, 标准, 规范, 合同, reference, references, cross-reference, other document, other tab, section, clause, standard, specification, contract, RFC -->
<!-- source: c30b2be55179 -->

# 跨文稿引用

标准常常引用其他标准，合同也会提及其附表，而且通常使用纯文本而不是链接。如果你将相关文稿作为标签页在同一窗口中打开，VectorPDF 就可以跟随这些引用。

## 跟随纯文本引用

1. 将相关文稿作为[同一窗口中的标签页](tabs-and-windows.md)打开。
2. 右键点按“Section 8.8.3 of [HTTP]”或“Clause 4.2 of the Master Agreement”这样的引用，或者选择引用后再右键点按它。
3. 选取以下操作之一：
   - **Go to** 匹配的标题，以预览该标题。你可以从预览前往该位置。
   - 在菜单打开时按住 ⌘，可将该命令改为 **Open**，它会直接前往该位置而不显示预览。
   - **Find in Other Tabs**，以搜索其他标签页中的文本。

VectorPDF 会将引用与另一文稿的大纲进行匹配；如果该文稿没有大纲，则与其标题进行匹配。如果同一标题出现在多个标签页中，预览会列出每一处。

## 指向已打开文稿的网页链接

有些文稿通过网页相互链接。例如，IETF RFC 文稿会链接到 rfc-editor.org。如果网页链接指向的文稿已在另一个标签页中打开，将指针悬停并按住 ⌘ 或用力点按时，会[在该标签页中预览](link-peek.md)，而不会打开浏览器。

## 将一组文稿放在一起

将经常一起使用的文稿存储为[标签页组](favorites-and-tab-groups.md)，这样就可以一步重新打开它们。

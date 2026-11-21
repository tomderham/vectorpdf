<!-- keywords: 标签页, 窗口, 新标签页, 新窗口, 程序坞, 子窗口, 锚点窗口, tab, tabs, window, windows, new tab, new window, Dock, child windows, anchor windows -->
<!-- source: f07082cac4f4 -->

# 标签页和窗口

## 标签页

VectorPDF 使用标准的 macOS 窗口标签页。

- **新建标签页：** 按下 ⌘T，或者点按标签页栏中的 + 按钮。
- **在新标签页中打开 PDF：** 按下 ⌥⌘O，或者将其拖移到已打开的文稿上。
- **新窗口：** 按下 ⌘N 可打开空白窗口，按下 ⌘O 可在新窗口中打开 PDF。
- **移动标签页：** 将其拖到另一个窗口的标签栏上，或拖出标签栏使其成为单独的窗口。
- **切换标签页：** 按下 ⇧⌘] 前往下一个标签页，按下 ⇧⌘[ 前往上一个标签页（Go > Next Tab 和 Go > Previous Tab）。⌃Tab 和 ⇧⌃Tab 也可以使用。

若要将打开的标签页存储为组，请右键点按文稿标题，然后选取 Save All Open Tabs as a Group。请参阅[个人收藏和标签页组](favorites-and-tab-groups.md)。

将相关文稿作为同一窗口的标签页，还能让 VectorPDF [跟随它们之间的引用](cross-document-references.md)。

## 查找打开的窗口 {#find-an-open-window}

Window 菜单和程序坞中的 VectorPDF 图标会按你打开的顺序列出打开的窗口，每个窗口的标签页缩进显示在其下方。带有标签页的窗口上下各有一条线，并以其标签页数量（或你打开它时所用的[标签页组](favorites-and-tab-groups.md)的名称）显示；勾号标出其当前标签页。选取窗口或标签页即可将其移到最前面。若要打开新窗口，请右键点按程序坞中的 VectorPDF 图标，然后选取 New Window。

窗口旁边：

- 勾号标出最前面的窗口。
- 菱形标出已最小化的窗口。
- 圆点标出某个标签页中有未存储更改的窗口。

锚点窗口不会列出：它们会随打开它们的标签页一起移到最前面。

## 锚点窗口 {#anchor-windows}

你可以在单独的小窗口中打开文稿中的任意位置，以便在阅读时让图或定义始终可见：

- 按住 ⌘ 点按链接。
- 右键点按链接、所选内容、页面上的某个位置、搜索结果或大纲条目，然后选取 **Open in New Window**。

这些窗口的顶部有一个横幅。点按它可跳回其显示的位置。点按横幅中的 **Close all Child Windows** 可关闭从同一文稿打开的所有窗口。关闭它们所属的文稿时，这些窗口也会关闭。

VectorPDF 不会打开重复的窗口：如果该位置已在某个窗口中打开，VectorPDF 会将该窗口移到前面。

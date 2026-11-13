<!-- keywords: 窗口, 工具栏, 边栏, 标签页, 开始屏幕, 界面, 页面指示器, 控制项, 附件, window, toolbar, toolbars, sidebar, tabs, start screen, interface, page indicator, controls, attachments, 状态栏, Inspector, status bar -->
<!-- source: fdb75158a744 -->
# VectorPDF 窗口

每个 VectorPDF 窗口都包含工具栏、边栏和文稿本身。一个窗口可以将多份文稿作为[标签页](tabs-and-windows.md)保存。

## 工具栏

| 控制项 | 作用 |
| --- | --- |
| 文稿标题 | 显示文稿名称。右键点按它可使用 Favorites 和 Tab Groups。 |
| Zoom | − 和 + 按钮可逐级缩放。点按百分比可键入自定值。 |
| Rotate Left 和 Rotate Right | 旋转视图。这不会更改已存储的 PDF。 |
| Two-Page Mode | 像翻开的书一样并排显示页面。 |
| Markup Toolbar | 显示[标记工具](text-markup.md)。 |
| Measurement Toolbar | 显示[测量工具](measure.md)。 |
| Page | 箭头每次移动一页。点按页码可键入要前往的页码。 |

有关这些控制项的更多信息，请参阅[缩放、旋转和页面布局](zoom-and-layout.md)。

## 边栏

使用边栏顶部的标签页可在以下内容之间切换：

- **Outline & Thumbnails：** [目录，或每一页的缩略图](outline-and-thumbnails.md)。
- **Search：** [当前文稿的结果](search.md)。
- **Anchors：** [你保存的位置](anchors.md)。
- **Document：**文稿除页面之外包含的内容：它的[图层](layers.md)、[附件](attachments.md)，以及（如果你在设置中打开）它的[表单栏位、签名、链接和目标](document-tab.md)。从标签页顶部的菜单中选择要显示的内容。只有当文稿至少包含其中一种时，这个标签页才会出现。
- **Comments：** [所有注释及其回复和状态](draw-and-notes.md#see-all-annotations)。
- **Ask About This Document：** [Agent](agent.md)。此标签页在 macOS 26 或更高版本上显示，除非你在 Settings 中关闭了 [Use Agent](settings.md)。

使用工具栏中的边栏按钮可显示或隐藏边栏。VectorPDF 会记住你为每份文稿显示还是隐藏了边栏。首次打开文稿时，边栏会显示，除非文稿只有一两页，且没有任何可在边栏中显示的内容：没有大纲、图层、注释或附件。带有附件或图层的短文稿打开时会显示 Document 标签页中的这些内容，带有注释的则显示 Comments 标签页。

## 附加工具栏

有三个工具栏会在需要时显示在主工具栏下方。可从 View 菜单中选取它们：

- **Markup** (⇧⌘A) 包含[注释工具](text-markup.md)。
- **Measurement** (⇧⌘M) 包含[测量工具](measure.md)。
- **Redact** (⌥⌘R) 包含[涂黑工具](redact.md)。

View 菜单还可以显示页面下方的状态栏、标尺、网格、页面旁边的 Inspector 以及角落里的导航器。请参阅[标尺、状态栏和 Inspector](rulers-and-inspector.md)。

## 右键菜单

右键点按或按住 Control 键点按文稿、边栏或工具栏时，出现的菜单中也有许多命令。请参阅[右键菜单](right-click-menus.md)。

## 页面指示器

更改页面时，文稿上方会短暂显示一个小的页面指示器，其中的箭头可用于移到上一页和下一页。显示 Measurement 工具栏时，它还会显示该页面的图纸比例。

## Start 屏幕

空白窗口或标签页会显示 Start 屏幕，其中包含拖放区域，然后是你的 Tab Groups、Favorites 和 Recent Documents。点按某一行可将其打开。将指针停放在某一行上并点按 ••• 按钮，或者右键点按该行，可在新标签页或新窗口中打开它、在访达 (Finder) 中显示它，或者移除它。

Start 屏幕最多列出三个 Tab Groups 和五个 Favorites。Favorites 菜单会列出全部项目。

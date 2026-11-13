<!-- keywords: 状态栏, 指针位置, 坐标, 页面大小, 纸张大小, 标尺, 参考线, 网格, 吸附, 单位, 毫米, 英寸, 点, Inspector, 字体, 字号, 颜色, 图像分辨率, 导航器, 字数, 字符数, status bar, pointer position, coordinates, page size, paper size, A4, Letter, ARCH, rulers, guides, grid, snap, units, millimeters, inches, points, font, font size, color, image resolution, dpi, ppi, line width, navigator, pan and zoom, word count, character count -->
<!-- source: a8ac6b2f855f -->

# 标尺、状态栏和 Inspector

这些功能显示页面上内容的位置及其组成。为了让阅读界面保持简洁，在你从 View 菜单中打开之前，它们都处于关闭状态。

## 状态栏

选取 View > Show Status Bar（⌘/）可在页面下方显示一条状态栏。它会显示：

- **指针在页面上的位置**，从页面左上角算起。在设有[图纸比例](drawing-scale.md)的页面上，还会以实际单位显示该位置。
- 指针下方页面或当前页面的**页面大小**；如果与某种纸张大小相符，还会显示其名称：A0 至 A6、B3 至 B5、Letter、Legal、Tabloid、ANSI C 至 E 以及 ARCH A 至 E。图纸集常常混用多种图幅，因此在页面之间切换时，显示内容会随之变化。
- **正在绘制的测量：**长度、角度，以及在水平（ΔX）和垂直（ΔY）方向上延伸的距离；到目前为止的周长及其最后一段；到目前为止的面积及其周长。请参阅[测量长度、面积和角度](measure.md)。
- **文本选择的大小**，以字数和字符数表示。

从状态栏右侧的菜单中选取单位：Millimeters、Inches 或 Points。标尺、网格和 Inspector 也使用这些单位。

## 标尺和参考线

选取 View > Rulers and Grid > Show Rulers（⌘R）可在页面的顶部和左侧显示标尺。标尺从左上角开始测量指针下方的页面，每个标尺上的一条线会显示指针的位置。

| 若要 | 请这样做 |
| --- | --- |
| 添加参考线 | 从标尺拖到页面上 |
| 移动参考线 | 拖移参考线 |
| 移除参考线 | 将参考线拖出页面 |
| 移除所有参考线 | 选取 View > Rulers and Grid > Clear Guides |

参考线属于你放置它们的页面。文稿打开期间它们会一直保留，但不会存储到文稿中。

## 网格

选取 View > Rulers and Grid > Show Grid（⌘'）可从左上角开始在每个页面上绘制网格。在 View > Rulers and Grid > Grid Spacing 中选择网格间距。每第五条线颜色较深。

在 View > Rulers and Grid 中打开 **Snap to Guides and Grid** 后，测量的点会吸附到指针附近的参考线，以及网格显示时吸附到网格，就像使用 Vertex Magnetic Snapping 时吸附到角一样。

## Inspector {#the-inspector}

选取 View > Show Inspector（⌃⌘I）可在页面旁边显示 Inspector。你也可以右键点按页面，然后选取 Inspect。

- **文本、图像和图形：**打开 Inspector 后，在 Select 模式下点按页面。Inspector 会显示该处绘制的内容，页面上也会为其显示外框：
  - **文本：**字体、字号、字符、颜色和色彩空间，以及字体是否包含在文件中。未包含的字体会用替代字体绘制，打印出来可能看起来不同。
  - **图像：**以像素计的大小、在页面上放置后的分辨率、在页面上的大小、色彩空间以及每个分量的位数。打印或优化前，请检查图像的分辨率。
  - **图形：**线条的粗细和颜色，或形状的填充颜色。
- **注释：**选择一个注释可查看其类型、作者、日期、图层、不透明度和颜色。若要移动注释，请键入其位置（从页面左上角算起的 **X** 和 **Y**），然后按下 Return 键。矩形、椭圆、文本框、标注、图章和修订云形还可以调整大小：键入其 **Width** 和 **Height**。

## 导航器

选取 View > Show Navigator（⌃⌘N）可在窗口角落显示当前页面的缩略图。屏幕上可见的部分会显示外框。拖移外框或点按缩略图，可在放大查看大图纸时四处移动。

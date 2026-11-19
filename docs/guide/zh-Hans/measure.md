<!-- keywords: 矩形, 圆形, 半径, 直径, 圆弧, 弧长, 测量, 长度, 距离, 尺寸, 周长, 面积, 角度, 正交, 吸附, measure, measurement, measurements, length, distance, dimension, perimeter, area, angle, ortho, snap, snapping, 编辑, 更改, 移动, 控制点, 偏移, edit, change, move, reshape, handle, offset, 计数, 清点, 统计, 符号, count, counting, tally, symbols, rectangle, circle, radius, diameter, arc, arc length, curve -->
<!-- source: fea799877718 -->

# 测量长度、面积和角度，以及计数

按下 ⇧⌘M 显示 Measurement 工具栏。如果你的图纸是按比例绘制的，请先[设置比例](drawing-scale.md)。

为确保准确，请在测量前放大视图。按下 Escape 键可取消正在进行的测量。再次按下 Escape 键或点按所选工具，即可放下工具。

## 测量工具

| 工具 | 使用方法 |
| --- | --- |
| Linear Dimension | 从一点拖移到另一点。 |
| Perimeter | 沿路径点按每个点。按下 Return 键或连按两下以完成。 |
| Polygon Area | 点按每个角。按下 Return 键、连按两下或点按第一个点以闭合形状。 |
| Rectangle Area | 从一个角拖移到对角。 |
| Circle | 从圆心拖移到边缘。标签会显示面积和直径，[状态栏](rulers-and-inspector.md)还会显示半径和周长。 |
| Arc Length | 依次点按圆弧的起点、圆弧上的一点和终点。标签会显示沿圆弧的长度及其半径。 |
| Vertex Angle | 点按第一条线上的一点，然后点按顶点，再点按第二条线上的一点。 |
| Count | 在组框中输入要计数的对象，例如插座，然后逐个点按。 |

## 计数图纸上的对象 {#count-things-on-a-drawing}

选取 Count 工具，然后在旁边的框中输入组名，例如插座或 A 型门，或者从框旁边的菜单中选取文稿中已有的组。每次点按都会放置一个标记，即 Measurement 工具栏颜色的圆点，工具栏会显示该组在此页面上有多少个。更改组名可计数其他对象；每个组分别计数。为每个组使用不同的颜色，以便在页面上区分它们。

若要移动标记，请用 Select 工具拖移它。若要移除标记，请右键点按它并选取 Delete Count Marker。[工程量表](takeoff.md)会显示每个页面上每个组的数量及合计。标记以小圆圈的形式存储在 PDF 中，因此其他 App 也会显示它们。

## 精确绘制

- **Ortho Lock** 使线条保持在 0°、45° 和 90°。按住 ⇧ 可针对单条线切换它：开启时可以任意角度测量，关闭时可以让线条保持笔直。
- **Vertex Magnetic Snapping** 使指针吸附到图纸中的角和端点。
- **参考线和网格：**打开 View > Rulers and Grid > Snap to Guides and Grid 后，点会吸附到你从标尺拖出的参考线上，以及网格显示时吸附到网格上。请参阅[标尺、状态栏和 Inspector](rulers-and-inspector.md)。
- **状态栏**（View > Show Status Bar）会在你绘制测量时显示比其标签更多的信息：它的角度、在水平和垂直方向上延伸的距离，或者面积到目前为止的周长。

## 更改测量结果

选取 Measurement 工具栏开头的箭头 **Select**，或者按下 Escape 键以放下测量工具。将指针移到测量结果上，虚线轮廓会显示它；点按即可选中。按住 ⇧ 点按可选择多个，也可以按住 ⌥ 在它们上方拖移。测量工具使用期间，点按会重新测量。

所选测量结果的各个点上有控制点。

| 若要 | 请执行以下操作 |
| --- | --- |
| 移动一个点 | 拖移它的控制点。Ortho Lock 和吸附的效果与测量时相同。 |
| 移动整个测量结果 | 拖移它的线条，或按下箭头键（按住 ⇧ 时每次移动 10 点）。 |
| 让尺寸线靠近或远离所测量的对象 | 拖移它的标签；尺寸线离开各点后，也可以直接拖移尺寸线。 |
| 更改颜色 | 使用 Measurement 工具栏中的颜色按钮选取颜色。 |
| 更改其线条粗细 | 在 Measurement 工具栏的线宽框中选取或输入粗细。 |

拖移时会重新计算数值。如果测量比视图更长，请拖移到窗口边缘以外来滚动。选取 Edit > Undo 可将测量结果恢复原样。已存储在 PDF 中的测量结果也可以更改。

若要选择面积，请点按它的边缘：点按其内部会选择那里的文本。

更改矩形、圆形或圆弧时，其形状会保持不变：拖移矩形的角、圆的圆心或边缘，或圆弧三个点中的任意一个。它们会存储为沿其轮廓的面积或长度，因此读取 PDF 测量的其他 App 也会将其显示为测量，并给出各自对轮廓的数值（对于圆形和圆弧，与 VectorPDF 的数值相差不到 0.05%）。

## 更改测量结果的外观

测量之前，请先在 Measurement 工具栏中使用颜色按钮和线宽框。选取以磅为单位的粗细，或输入 0.1 到 72 磅之间的值。新的测量结果为灰色、1.5 磅粗，除非你另行选取。VectorPDF 会记住你的选择，Markup 工具栏则保留自己的颜色和粗细。若要更改已创建的测量结果的颜色或粗细，请将其选中，然后在 Measurement 工具栏中选取颜色或粗细。粗细会存储在 PDF 中。

## 保留或移除测量结果

测量是注释，会在你[存储](save.md)时保存在 PDF 中。若要删除测量，请右键点按它，然后选取删除命令，例如 Delete Dimension、Delete Area Takeoff、Delete Circle Measurement 或 Delete Count Marker。

若要列出所有测量结果，请参阅[工程量表](takeoff.md)。

<!-- keywords: 测量, 长度, 距离, 尺寸, 周长, 面积, 角度, 正交, 吸附, measure, measurement, measurements, length, distance, dimension, perimeter, area, angle, ortho, snap, snapping, 编辑, 更改, 移动, 控制点, 偏移, edit, change, move, reshape, handle, offset -->
<!-- source: ce12181269d9 -->

# 测量长度、面积和角度

按下 ⇧⌘M 显示 Measurement 工具栏。如果你的图纸是按比例绘制的，请先[设置比例](drawing-scale.md)。

为确保准确，请在测量前放大视图。按下 Escape 键可取消正在进行的测量。再次按下 Escape 键或点按所选工具，即可放下工具。

## 测量工具

| 工具 | 使用方法 |
| --- | --- |
| Linear Dimension | 从一点拖移到另一点。 |
| Perimeter | 沿路径点按每个点。按下 Return 键或连按两下以完成。 |
| Polygon Area | 点按每个角。按下 Return 键、连按两下或点按第一个点以闭合形状。 |
| Vertex Angle | 点按第一条线上的一点，然后点按顶点，再点按第二条线上的一点。 |

## 精确绘制

- **Ortho Lock** 使线条保持在 0°、45° 和 90°。按住 ⇧ 可针对单条线切换它：开启时可以任意角度测量，关闭时可以让线条保持笔直。
- **Vertex Magnetic Snapping** 使指针吸附到图纸中的角和端点。

## 更改测量结果

按下 Escape 键或点按所选工具以放下测量工具，然后点按一个测量结果将其选中。它的各个点上会出现控制点。

| 若要 | 请执行以下操作 |
| --- | --- |
| 移动一个点 | 拖移它的控制点。Ortho Lock 和吸附的效果与测量时相同。 |
| 移动整个测量结果 | 拖移它的线条，或按下箭头键（按住 ⇧ 时每次移动 10 点）。 |
| 让尺寸线靠近或远离所测量的对象 | 拖移它的标签；尺寸线离开各点后，也可以直接拖移尺寸线。 |
| 更改颜色 | 使用 Measurement 工具栏中的颜色按钮选取颜色。 |

拖移时会重新计算数值。选取 Edit > Undo 可将测量结果恢复原样。已存储在 PDF 中的测量结果也可以更改。

若要选择面积，请点按它的边缘：点按其内部会选择那里的文本。

## 更改测量结果的外观

测量之前，请先在 Measurement 工具栏中使用颜色按钮并设置线条粗细。若要更改已创建的测量结果的颜色，请将其选中，然后选取颜色。

## 保留或移除测量结果

测量结果属于注释，会在你[存储](save.md)时保存在 PDF 中。若要删除测量结果，请右键点按它，然后选取相应的删除命令，例如 Delete Dimension 或 Delete Area Takeoff。

若要列出所有测量结果，请参阅[工程量表](takeoff.md)。

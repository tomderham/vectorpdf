<!-- keywords: LaTeX, TeX, SyncTeX, 正向搜索, 反向搜索, 源代码, 源文件, 编辑器, 跳转到源代码, LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->
<!-- source: a865c846e0d7 -->

# 在 LaTeX 源代码和 PDF 之间跳转

如果你用 LaTeX 写作，VectorPDF 可以把你从 PDF 中的某处带到生成它的源代码行，也可以从源代码行带到它在 PDF 中生成的位置。这使用的是 SyncTeX：TeX 使用 `-synctex=1` 编译时会开启它。大多数 LaTeX 编辑器都是这样编译的。

SyncTeX 适用于旁边有同名 SyncTeX 文件的 PDF：`paper.pdf` 和 `paper.synctex.gz`。文件夹中的其他 PDF 不受影响。

## 选择编辑器

1. 选取 VectorPDF > Settings，然后点按 LaTeX (SyncTeX) 旁边的 Set Up…。
2. 在 Source Editor 中选择你的编辑器：Visual Studio Code、VSCodium、Cursor、Zed、Sublime Text、BBEdit、TextMate、MacVim、Emacs 或 TeXstudio。
3. 如果你的编辑器不在列表中，请选择 Other，然后输入在某一行打开文件的命令。用 `%file` 表示文件，用 `%line` 表示行，例如 `myeditor +%line %file`。

Settings 会在编辑器下方显示它找到的程序。如果显示找不到程序，请安装编辑器的命令行工具，或者选择 Other 并填写程序的完整路径。

## 从 PDF 跳到源代码

按住 ⇧⌘ 点按 PDF 中的某处。你的编辑器会在生成该处的行打开源文件。

你也可以右键点按并选取 **Show in Editor**。对于带有 SyncTeX 文件的 PDF，它位于菜单顶部。

## 从源代码跳到 PDF

你的编辑器通过运行 VectorPDF 自带的 `displayline`，请 VectorPDF 显示某一行：

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

VectorPDF 会将 PDF 移到最前面（如果尚未打开则打开它），并用红色短暂高亮显示该行。只有当该行不在屏幕上时才会滚动。在 LINE 前加上 `-g`，可让 VectorPDF 留在编辑器后面。

`displayline` 接受的参数与 Skim 的相同。如果你的编辑器有针对 Skim 的设置，请改用 VectorPDF 的 `displayline`。

### Visual Studio Code

使用 LaTeX Workshop 扩展时，将以下几行添加到你的设置中。要打开设置，请在命令面板中选取 Preferences: Open User Settings (JSON)。

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

然后在 Visual Studio Code 中，按 ⌥⌘B 编译，按 ⌥⌘V 在 VectorPDF 中打开 PDF，按 ⌥⌘J 显示你所在的行。有了最后一项设置，每次编译后 VectorPDF 也会显示该行。

## 写作时

编辑器重新编译 PDF 时，VectorPDF 会重新载入它，并保留你的位置、缩放、旋转和页面布局。如果文件仍在写入，VectorPDF 会等它写完。

## 如果不起作用

- **菜单中没有 Show in Editor：** 该 PDF 没有 SyncTeX 文件。请开启 SyncTeX 进行编译，并将 SyncTeX 文件放在 PDF 旁边，或放在其旁边名为 build 或 out 的文件夹中。
- **No Source Here：** 该处（例如页边或图片）没有对应的源代码行。请点按文本。
- **VectorPDF 中没有反应：** 请检查你的编辑器是否运行 VectorPDF 的 `displayline`，以及自上次更改源代码以来是否已开启 SyncTeX 编译 PDF。
- **安装 TeX 后编辑器仍找不到它：** 退出编辑器，然后重新打开。

<!-- keywords: 设置, 偏好设置, 选项, 更新, 检查更新, 浏览器, 作者, 注释作者, 存储空间, 磁盘空间, 清除, 移除数据, 删除数据, 卸载, settings, preferences, options, updates, update, check for updates, browser, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->
<!-- source: 91c5b0e9ab3d -->

# 设置

选取 VectorPDF > Settings，或者按下 ⌘, 键。

| 设置 | 作用 |
| --- | --- |
| Annotation Author | 随注释和回复一起存储的名字。如果留空，VectorPDF 会使用你的 Mac 用户名。 |
| Use Agent | 在 macOS 26 或更高版本上，在边栏中显示 [Ask About This Document](agent.md) 标签页。 |
| AI Synthesis Engine | 在 macOS 27 上，选择[由什么撰写 Agent 的回答](agent-engines.md)。 |
| PDF Color | 设置[页面的外观](pdf-colors.md)：Follow System、Light、Dark 或 Sepia。 |
| Open Links In | 选择用于打开网页链接的浏览器。 |
| LaTeX (SyncTeX) | 选择按住 ⇧⌘ 点按 PDF 时用来打开 [LaTeX 源代码](latex.md)的编辑器。 |
| Ignored Search Patterns | 列出 [Smart Search 要跳过的文本](search.md#ignore-clutter-in-the-text)。 |
| Digital Stamp | 创建、更改或删除你的[图章](stamps.md)。 |
| Sync reading positions with iCloud | 在你的其他 Mac 上保留你的[页面、缩放比例、锚点](reading-positions.md)和[最近搜索](search.md)。 |
| Storage | 显示 VectorPDF 的数据占用多少空间，并可[将其清除](#free-up-space-or-remove-data)。 |
| Automatically check for updates | 大约每天在 GitHub 上检查一次新版本。点按 Check Now 可随时检查。 |

## 释放空间或移除数据 {#free-up-space-or-remove-data}

在 Storage 下，设置会显示每类数据占用的空间：

- **Agent 索引：** Agent 为回答关于文稿的问题而创建的内容。点按 Clear 将其删除；下次对该文稿使用 Agent 时会重新编制索引。VectorPDF 会先删除最久未使用的索引，使其保持在 500 MB 以下，并在文稿不存在时删除其索引。
- **阅读历史：** 每个文稿的最后页面、缩放比例、锚点和最近搜索。点按 Clear 可在这台 Mac 和 iCloud 中将其清除。
- **临时文件：** 编辑、存储、打印或导出时创建的副本，以及下载的更新。VectorPDF 下次打开时会删除遗留的文件。

要移除 VectorPDF 存储的所有内容，请点按 Remove All VectorPDF Data。这也会移除你的设置、个人收藏、标签页组、图章和 API 密钥，然后退出 VectorPDF。你的文稿不受影响。请先存储或关闭有未存储更改的文稿。

## 更新 VectorPDF

选取 VectorPDF > Check for Updates。如果有新版本，请点按 Download。下载完成后，点按 **Quit and Open Installer**，然后将 VectorPDF 拖移到“应用程序”文件夹。

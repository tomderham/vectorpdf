<!-- keywords: damaged, corrupt, unreadable, 故障排除, 问题, 不起作用, 帮助, 修复, 支持, troubleshooting, problem, problems, not working, help, fix, support -->
<!-- source: 0ca329d057c7 -->

# 故障排除

## 我无法选择文本、跟随链接或使用标记工具

请检查是否有 Markup 或 Measurement 工具处于活跃状态。按下 Escape 键或再次点按所选工具，可返回文本选择状态。

## 搜索未找到任何内容

- 这些页面可能是扫描页面。请参阅[搜索和选择扫描页面上的文本](scanned-pages.md)。
- 检查[搜索选项](search.md#search-options)中的 Match Case 和 Whole Word 是否已关闭，以及 Smart Search 是否已打开。
- 如果标记打断了文本，请添加[忽略的模式](search.md#ignore-clutter-in-the-text)。

## 按住 ⌘ 时不显示预览

Link Peek 适用于文稿中的链接，以及指向已在其他标签页中打开的文稿的网页链接。纯文本引用不是链接，因此请改为右键点按它们。请参阅[跨文稿引用](cross-document-references.md)。

此外，VectorPDF 窗口必须是活跃窗口。

## 找不到对其他文稿的引用

将另一份文稿作为标签页在同一窗口中打开。不会搜索单独的窗口。

## 文档显示已损坏

如果 VectorPDF 在文件中找不到任何页面，它会提示无法打开该文件。文件可能已损坏或不完整，也可能使用了 VectorPDF 无法读取的功能。请尝试重新下载，或在其他 PDF 应用中打开。

## 无法打开云端文稿

检查你的网络连接，以及文件能否在访达 (Finder) 中下载，然后重试。

## Agent 不可用或只显示段落

Agent 需要 macOS 26 或更高版本，而在设备端撰写回答需要打开 Apple 智能并使其准备就绪。如果建立索引失败，请点按 Ask About This Document 标签页中的 Retry。请参阅[选择 Agent 的回答方式](agent-engines.md)。

## 在线模型没有回答

检查 [Settings](settings.md) 中的 API 密钥和模型，以及你在该服务的账户是否有余额。如果服务出现故障，VectorPDF 会在设备端回答。

## 我的更改不见了

更改需要[存储](save.md)后才会保留。如果其他应用在你有未存储更改时更改了文件，选取 Reload from Disk 会放弃这些更改。

## 帮助不显示本手册

只有当 VectorPDF 位于“应用程序”文件夹中时，Tips 才能显示本手册。请将它移到该文件夹，然后再次选取 Help > VectorPDF Help。

## 获取更多帮助

请在 [GitHub](https://github.com/tomderham/vectorpdf/issues) 上报告问题或提出疑问。如果可以分享，提供一个 PDF 样本会很有帮助。

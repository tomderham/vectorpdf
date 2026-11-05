<!-- keywords: 隐私, 数据, 网络, 遥测, 分析, 安全性, 最近搜索, privacy, data, network, telemetry, analytics, iCloud, security -->
<!-- source: 936fa61fbdbf -->

# 隐私

VectorPDF 没有账户、分析、遥测或崩溃报告功能。你的文稿在 Mac 上处理，其中的任何内容都不会发送给开发者。

## 哪些功能使用网络

- **检查更新：** VectorPDF 大约每天向 GitHub 查询一次最新版本，你选取 Check for Updates 时也会查询。该请求不包含有关你或你的文稿的任何信息。你可以在 [Settings](settings.md) 中关闭此功能。
- **Agent：** 使用 On-Device 引擎时，不会有任何内容离开你的 Mac。[Private Cloud Compute 和在线模型](agent-engines.md)会发送你的问题和文稿中的段落，并且仅在你提问时发送。设置在线模型时，还会使用你的密钥列出其模型并发送一条简短的测试信息。
- **iCloud：** 你的阅读状态保存在你自己的 iCloud 账户中，包括文件位置、上次阅读的页面和缩放比例，以及锚点的名称、摘录和页面。文稿、文稿全文和锚点缩略图不会上传。你的最近搜索也保存在那里。
- **你点按的链接**会在浏览器中打开。
- **Apple 服务：** 翻译、Look Up、语音和 OCR 由 macOS 提供，可能会从 Apple 下载语言文件。接力会与你的其他设备共享你正在阅读的文稿和页面。

## 哪些内容存储在你的 Mac 上

VectorPDF 会存储你的偏好设置、个人收藏、标签页组、阅读位置、锚点和图章。它还会保留用于 Agent 的文稿索引、锚点缩略图，以及含有未存储页面编辑或涂黑操作的文稿的临时工作副本，并在用完后将其删除。

它还会存储每个文稿的最近搜索。要查看这些内容占用多少空间或将其清除，请使用 [Settings](settings.md#free-up-space-or-remove-data) 中的 Storage。

在线模型的 API 密钥存储在你的登录钥匙串中。

有关完整详情，请参阅 [GitHub 上的隐私政策](https://github.com/tomderham/vectorpdf/blob/main/PRIVACY.md)。

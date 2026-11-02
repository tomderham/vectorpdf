<!-- keywords: Agent, AI, 人工智能, 引擎, 模型, 在线模型, API 密钥, 隐私, 回答, AI Synthesis Engine, On-Device, Private Cloud Compute, Online Model, OpenAI, Gemini, OpenRouter, API key, model -->
<!-- source: dbbd02de21b5 -->

# 选择 Agent 的回答方式

相关段落的搜索始终在你的 Mac 上进行。你可以在 VectorPDF > Settings > AI Synthesis Engine 中选择由什么来撰写回答。此设置需要 macOS 27。

| 引擎 | 工作方式 | 哪些内容会离开你的 Mac |
| --- | --- | --- |
| On-Device | 你的 Mac 上的 Apple 智能 | 无 |
| Private Cloud Compute | Apple 的服务器，用于生成更长、更详细的回答 | 你的问题和用到的段落，它们会发送到 Apple 的 Private Cloud Compute |
| Online Model (your API key) | 由你选择的服务，费用计入你在该服务的账户 | 你的问题、段落（如果是简短文稿，则为全部文本）以及之前的对话 |

在 macOS 26 上，Agent 在设备端回答。

只有为此进行过签名的 VectorPDF 版本才会显示 Private Cloud Compute。从 GitHub 下载的版本在设备端回答。

## 使用在线模型

1. 在 Settings 中，将 AI Synthesis Engine 设为 Online Model。
2. 选取一项服务：OpenAI、Google Gemini 或 OpenRouter。
3. 输入你的 API 密钥。每项服务都提供了获取密钥的链接。密钥存储在你的登录钥匙串中。
4. 选取一个模型。

如果该服务无法回答，VectorPDF 会在设备端回答。

> **警告：** 你发送的内容受该服务的隐私政策和条款约束。使用免费的 Gemini 密钥时，Google 可能会用你发送的内容改进其产品，并且可能有人工审阅这些内容，因此请勿发送机密文稿。请参阅[隐私](privacy.md)。

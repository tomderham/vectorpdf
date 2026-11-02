<!-- keywords: 密码, 加密, 保护, 受保护, 安全性, 权限, 锁定, password, passwords, encrypt, encrypted, encryption, AES, protect, protected, security, permissions, lock, PDF -->
<!-- source: 27a9d624a54a -->

# 密码和加密

## 打开受保护的 PDF

打开受保护的 PDF 时，VectorPDF 会要求你输入密码。如果你点按 Cancel，文稿会保持关闭状态。

## 加密副本

1. 选取 File > Save Encrypted with Password (⌥⌘S)。
2. 选取名称和位置。
3. 输入两次密码，然后点按 Encrypt & Save。

该副本使用 AES-256 加密，需要密码才能打开。

> **警告：** 请妥善保管密码。如果丢失密码，将无法恢复已加密的 PDF。

## 查看文稿的权限

若要查看文稿作者允许的操作（例如打印或拷贝），请选取 File > Document Properties (⌘I)，然后点按 Security。请参阅[文稿属性](document-properties.md)。

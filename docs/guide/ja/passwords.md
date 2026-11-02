<!-- keywords: パスワード, 暗号化, 保護, セキュリティ, アクセス権, ロック, password, passwords, encrypt, encrypted, encryption, AES, protect, protected, security, permissions, lock, PDF -->
<!-- source: 27a9d624a54a -->

# パスワードと暗号化

## 保護された PDF を開く

保護された PDF を開くと、VectorPDF がパスワードを要求します。Cancel をクリックすると、書類は閉じたままになります。

## 暗号化したコピーを作成する

1. File > Save Encrypted with Password (⌥⌘S) を選択します。
2. 名前と場所を選択します。
3. パスワードを 2 回入力して、Encrypt & Save をクリックします。

コピーは AES-256 で暗号化され、開くにはパスワードが必要になります。

> **警告:** パスワードは安全に保管してください。パスワードを忘れると、暗号化した PDF を復元する方法はありません。

## 書類のアクセス権を確認する

プリントやコピーなど、書類の作成者が許可している内容を確認するには、File > Document Properties (⌘I) を選択してから、Security をクリックします。[書類のプロパティ](document-properties.md)を参照してください。

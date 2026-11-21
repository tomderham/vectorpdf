<!-- keywords: 手写签名, 签名, 签署, 图章, 姓名首字母, stamp, stamps, signature, signatures, sign, signing, initials, PDF, handwritten signature, digital signature, sign with certificate, certificate, p12, pfx, keychain, timestamp, certify, lock fields, which signature -->
<!-- source: 132d42959c5b -->

# 签署文稿

签名有两种方式，作用各不相同。两者都在 Markup 工具栏（⇧⌘A）中形似签名的 Sign 按钮上。

| | 手写签名 | 数字签名 |
| --- | --- | --- |
| 是什么 | 页面上你的签名或姓名首字母的图片 | 用你的证书制作并保存在文件中的签名 |
| 表明谁签了名 | 否：任何人都能粘贴图片 | 是，如果证书来自读者信任的机构 |
| 表明文稿此后未被更改 | 否 | 是 |
| 需要什么 | 无：绘制、键入或选取图像 | 来自你的组织或证书颁发机构的签名证书 |
| 之后能否移除 | 能，就像注释一样 | 只能恢复到签名前存储的副本 |

在图片就足够的场合（例如非正式表单），手写签名即可。对于合同、审批以及以后可能需要有人检查的任何内容，请使用数字签名。数字签名也可以在其框中显示你的手写签名。

## 添加手写签名 {#add-your-handwritten-signature}

1. 显示 Markup 工具栏（⇧⌘A），点按 Sign 按钮，然后选取 Add Handwritten Signature。第一次使用时，VectorPDF 会要求你制作签名：
   - **Draw：** 使用触控板或鼠标签名。
   - **Type：** 输入你的姓名或姓名首字母，然后选取字体。
   - **Image：** 选取 PNG 或 JPEG 文件。如果你选取 **Transparent background**，页面内容会透过图像的背景显示出来。
2. 点按要放置它的位置。

然后，拖移签名可移动它，拖移角可调整其大小。若要移除签名，请选择它并按下 Delete 键，或者右键点按它并选取 Delete Signature。

VectorPDF 会将你的签名保存在这台 Mac 上供下次使用。若要更改或删除它，请选取 VectorPDF > Settings，点按 General，然后使用 Handwritten Signature 旁边的按钮。

## 使用证书签名 {#sign}

若要签名，你需要一个带有私钥的签名证书。你的组织或证书颁发机构可以为你提供，通常是带密码的 .p12 或 .pfx 文件。钥匙串中的证书可以直接使用。

1. 点按 Markup 工具栏中的 Sign 按钮并选取 Sign with Certificate，或选取 Edit > Sign with Certificate。然后在页面上要放置签名的位置拖出一个框，或点按以放置常规大小的框。按下 Esc 键可停止。如果文稿有空的签名栏位，你也可以点按该栏位并选取 Sign with Certificate。
2. 选取你的证书。预览会显示签名的样子。若要使用文件，请点按 **Choose Certificate File**，然后输入它的密码。该文件只为这次签名读取，不会添加到你的钥匙串。
3. 如有需要，输入原因（例如“我批准此文稿”）和签名地点。如果你已制作[手写签名](#add-your-handwritten-signature)，可以在栏位中显示它。否则会显示你的姓名。
4. 如有需要，在 After Signing 下选取：
   - **Certify**（文稿尚无人签名时）：指定今后哪些更改仍让文稿保持有效：填写表单、签名和添加注释；填写表单和签名；或不允许任何更改。经认证的文稿会向每位检查者显示为已认证，不被允许的后续更改会使你的签名失效。
   - **Lock form fields**（适用于表单）：所有栏位或你选取的栏位会变为只读，保持你签名时的值。
5. 点按 **Sign**，然后选取签名文稿的存储位置。VectorPDF 会建议在原文稿旁边存储一个名称以“(signed)”结尾的副本，并保持原文稿未签名；随后签名副本会在原文稿的位置打开。若要为原文稿本身签名，请改为选取原文稿并点按 **Replace**。

签名针对的是存储后的文稿，因此签名总会存储文稿。如果文稿有未存储的更改，VectorPDF 会先询问是否存储；这些更改会成为你所签内容的一部分。macOS 可能会要求你允许 VectorPDF 使用证书的密钥。

签名无法再从已签名的文件中移除：它的作用就是让任何人都能看出文稿此后没有被更改。为副本签名会保留未签名的原文稿，以便再次签名或修改。

除非你锁定栏位或将文稿认证为允许更少的更改，签名不会改变文稿中的其他表单栏位，因此其他人仍可填写它们、同样进行签名或添加注释，而不会使你的签名失效。之后的每个签名也会以同样方式添加在之前的签名之后。

该签名是使用 SHA-256 的 PKCS #7 签名，包含你的证书以及颁发它的机构的证书。它记录你的 Mac 上的时间。

若要让时间戳服务器担保你签名的时间，请打开 **Add a timestamp** 并输入其地址（你的组织可能有自己的服务器；也有免费的，例如 DigiCert 的 `http://timestamp.digicert.com`）。有了时间戳，即使你的证书过期，也能按签名时的状态检查你的签名。服务器只会收到签名的指纹，不会收到文稿的任何内容。以 `http://` 开头的地址适用于知名的公共时间戳服务器（例如 DigiCert、Sectigo、GlobalSign、Entrust 和 Apple 的服务器）以及本地网络中的服务器；对于其他服务器，请使用其 `https://` 地址。如果无法连接服务器，则不会签名，文稿保持原样。

若要检查文稿中的签名，请参阅[检查数字签名](digital-signatures.md)。

## 签署表单

如果表单有签名栏位，请点按栏位中的 **Sign**，然后选取 Add Handwritten Signature 或 Sign with Certificate。请参阅[填写表单](forms.md)。

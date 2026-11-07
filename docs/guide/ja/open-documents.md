<!-- keywords: 開く, PDF を開く, ファイルを開く, PDF, 最近使った項目, パスワード, クラウド, 再読み込み, ドラッグ, 電子書籍, コミック, open, open PDF, open file, PDF, recent, password, cloud, iCloud Drive, Google Drive, Dropbox, OneDrive, Box, reload, drag, EPUB, e-book, ebook, XPS, OXPS, CBZ, comic, FB2, FictionBook -->
<!-- source: 48a137d82361 -->

# 書類を開く

## PDF を開く

- **新しいウインドウで開く:** File > Open PDF を選択するか、⌘O を押します。
- **新しいタブで開く:** File > Open PDF in New Tab を選択するか、⌥⌘O を押します。
- **Finder から開く:** PDF を右クリックして、Open With > VectorPDF (「このアプリケーションで開く」> VectorPDF) を選択します。すべての PDF を VectorPDF で開くようにするには、PDF を選択し、Finder で File > Get Info (「ファイル」>「情報を見る」) を選択して、“Open with” (「このアプリケーションで開く」) を変更し、Change All (「すべてを変更」) をクリックします。
- **ドラッグして開く:** PDF を Start 画面にドラッグするとそこで開き、開いている書類にドラッグすると新しいタブで開きます。
- **リストから開く:** File > Open Recent を選択するか、[Favorites](favorites-and-tab-groups.md) メニューを使用します。Start 画面では、書類を右クリックして新しいタブやウインドウで開くことができます。

## 電子書籍、コミック、XPS 書類

VectorPDF では、EPUB や FictionBook (FB2) の電子書籍、CBZ のコミックアーカイブ、XPS 書類も、PDF と同じ方法で開けます。電子書籍は読みやすいようにページに組まれます。

これらの書類は、読む、目次をたどる、検索する、テキストを選択してコピーする、[アンカー](anchors.md)を追加する、といった操作ができます。読み取り専用で開くため、VectorPDF では保存できません。マークアップ、計測、墨消し、ページ編集は使用できず、Save は淡色表示になります。

## パスワードで保護された PDF

保護された PDF を開くと、VectorPDF がパスワードを要求します。[パスワードと暗号化](passwords.md)を参照してください。

## クラウドストレージ上の PDF

VectorPDF は、iCloud Drive、Google Drive、Dropbox、OneDrive、Box のファイルを認識します。ファイルがまだ Mac にない場合は、VectorPDF がファイルをダウンロードしてから開き、進行状況を表示します。ダウンロードが完了しなかった場合はメッセージが表示されるので、接続できるようになってからもう一度試すことができます。

## ファイルが変更されたとき

VectorPDF は、開いている各ファイルを監視しています。別のアプリがファイルを変更すると、書類は自動的に再読み込みされます。LaTeX などのツールから PDF を生成しながら、開いたままにしておきたい場合に便利です。再読み込みしても、表示位置、拡大率、回転、ページレイアウトは保たれます。また、書き込み中のファイルは書き込みが終わるまで待ってから読み込みます。LaTeX については[LaTeX ソースと PDF の間を移動する](latex.md)も参照してください。

保存していない変更がある場合は、変更を破棄して **Reload from Disk** を実行するか、**Keep My Changes** を選択するかを確認されます。

Finder でファイルを移動したり名前を変更したりしても、開いている書類はそのファイルを追跡します。

## 書類を閉じる

タブやウインドウは通常どおり閉じます。保存していない変更がある場合は、保存するかどうかを確認されます。VectorPDF は[読んでいた場所](reading-positions.md)を記憶し、次回に備えます。

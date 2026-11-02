<!-- keywords: 開く, PDF を開く, ファイルを開く, 最近使った書類, パスワード, クラウド, 再読み込み, ドラッグ, open, open PDF, open file, PDF, recent, password, cloud, iCloud Drive, Google Drive, Dropbox, OneDrive, Box, reload, drag -->
<!-- source: fc51842f2339 -->

# 書類を開く

## PDF を開く

- **新しいウインドウで開く:** File > Open PDF を選択するか、⌘O を押します。
- **新しいタブで開く:** File > Open PDF in New Tab を選択するか、⌥⌘O を押します。
- **Finder から開く:** PDF を右クリックして、Open With > VectorPDF (「このアプリケーションで開く」> VectorPDF) を選択します。すべての PDF を VectorPDF で開くようにするには、PDF を選択し、Finder で File > Get Info (「ファイル」>「情報を見る」) を選択して、“Open with” (「このアプリケーションで開く」) を変更し、Change All (「すべてを変更」) をクリックします。
- **ドラッグして開く:** PDF を Start 画面にドラッグするとそこで開き、開いている書類にドラッグすると新しいタブで開きます。
- **リストから開く:** File > Open Recent を選択するか、[Favorites](favorites-and-tab-groups.md) メニューを使用します。Start 画面では、書類を右クリックして新しいタブやウインドウで開くことができます。

## パスワードで保護された PDF

保護された PDF を開くと、VectorPDF がパスワードを要求します。[パスワードと暗号化](passwords.md)を参照してください。

## クラウドストレージ上の PDF

VectorPDF は、iCloud Drive、Google Drive、Dropbox、OneDrive、Box のファイルを認識します。ファイルがまだ Mac にない場合は、VectorPDF がファイルをダウンロードしてから開き、進行状況を表示します。ダウンロードが完了しなかった場合はメッセージが表示されるので、接続できるようになってからもう一度試すことができます。

## ファイルが変更されたとき

VectorPDF は、開いている各ファイルを監視しています。別のアプリがファイルを変更すると、書類は自動的に再読み込みされます。LaTeX などのツールから PDF を生成しながら、開いたままにしておきたい場合に便利です。

保存していない変更がある場合は、変更を破棄して **Reload from Disk** を実行するか、**Keep My Changes** を選択するかを確認されます。

Finder でファイルを移動したり名前を変更したりしても、開いている書類はそのファイルを追跡します。

## 書類を閉じる

タブやウインドウは通常どおり閉じます。保存していない変更がある場合は、保存するかどうかを確認されます。VectorPDF は[読んでいた場所](reading-positions.md)を記憶し、次回に備えます。

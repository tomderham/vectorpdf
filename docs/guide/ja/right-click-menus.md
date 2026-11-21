<!-- keywords: 右クリック, Control キーを押しながらクリック, コンテキストメニュー, ショートカットメニュー, right-click, right click, Control-click, context menu, context menus, shortcut menu -->
<!-- source: f9e1ad75cfd5 -->

# 右クリックメニュー

右クリックするか、Control キーを押しながらクリックすると、ポインタの下にあるものに対するコマンドが表示されます。表示されるメニューは、クリックした場所によって異なります。ページ上のどこでも、メニューの最後に Inspect があり、そこに描かれているものを [Inspector](rulers-and-inspector.md#the-inspector) で開きます。

## 書類内

| 右クリックする場所 | コマンド |
| --- | --- |
| 選択したテキスト | Copy Text、Look Up、Translate Selection、Start Speaking または Stop Speaking、Highlight、Underline、Strikethrough、Create Anchor、Create Anchor and Open in New Window、Open in New Window |
| 選択した領域 | Highlight Area、Copy Extracted Text、Copy Screenshot、Save Screenshot As、Create Anchor、Create Anchor and Open in New Window、Open in New Window |
| リンク | Create Anchor、Create Anchor and Open in New Window、Open in New Window |
| ハイライト、下線、取り消し線 | Comments…、および対応する Remove コマンド |
| テキストボックス | Comments…、Edit Text Box、および削除コマンド |
| 吹き出し | Comments…、Edit Callout Note、Line Ending、および削除コマンド |
| メモ、または長方形、楕円、リビジョンクラウドの輪郭 | Comments… と削除コマンド |
| 線または矢印 | Comments…、Line Ending、削除コマンド |
| 描画、スタンプ、測定値 | Comments…、および削除コマンド |
| 複数選択した注釈のいずれか | Align(端と中央。3 つ以上では Distribute)、個数付きの Delete |
| 以前に書類に保存された、またはほかのアプリで作成された図形、クラウド、線、メモ、スタンプ、テキストボックス | Comments…、線の場合は Line Ending、削除コマンド |
| 以前に書類に保存された、またはほかのアプリで作成されたハイライト、描画、計測 | Comments… と、ページ上のほかの場所と同じコマンド |
| ページ上のその他の場所 | Create Anchor、Create Anchor and Open in New Window、Open in New Window |

プレーンテキストの参照を右クリックしたときに、関連する書類が別のタブで開いている場合は、メニューに[その参照に移動または検索する](cross-document-references.md)コマンドも表示されます。

SyncTeX を有効にして LaTeX で作成した PDF では、書類内のすべてのメニューの先頭に **Show in Editor** があり、クリックした位置の[ソースの行](latex.md)を開きます。

[レイヤー](layers.md)のある書類では、注釈のメニューに **Layer** もあり、別のレイヤーに移動したり、どのレイヤーからも外したりできます。

## サイドバー内

| 右クリックする場所 | コマンド |
| --- | --- |
| アウトラインの項目 | Create Anchor、Create Anchor and Open in New Window、Open in New Window、Add Entry After、Add Entry Inside、Rename、Go Here Instead、Move Up、Move Down、Indent、Outdent、Delete Entry、Build Outline from Headings。[アウトラインを編集する](outline-and-thumbnails.md#edit-the-outline)を参照してください。 |
| サムネール | Rotate Clockwise、Rotate Counterclockwise、Rotate 180°、Duplicate Page、Insert Blank Page、Insert Pages from PDF、Save selected page as a PDF、Export Page as Image、Move Page Up、Move Page Down、Delete Page。複数のページを選択している場合は、Delete 3 Pages のようにコマンドにページ数が示されます。[ページを並べ替える](pages.md)を参照してください。 |
| 検索結果 | Create Anchor、Create Anchor and Open in New Window、Open in New Window |
| アンカー | Open in New Window または Close Window、Copy Text、Copy Screenshot、Delete Anchor |
| Comments タブの注釈 | Show on Page、Comments…、Delete |
| Document タブのレイヤー | Put New Annotations Here または Stop Putting New Annotations Here。[レイヤーの表示と非表示](layers.md)を参照してください。 |
| Document タブの添付ファイル | Quick Look、Open、Save As…、およびページに添付されたファイルの場合は Show on Page。[PDF に添付されたファイル](attachments.md)を参照してください。 |
| Document タブのフォームフィールド | Show on Page、Copy Name、Copy Value。[フォームフィールド、署名、リンク、移動先](document-tab.md)を参照してください。 |
| Document タブの署名 | Show on Page、Show Certificate。[デジタル署名で署名する、確認する](digital-signatures.md)を参照してください。 |
| Document タブのリンク | Show on Page、Go to Destination または Open Link、および Web リンクの場合は Copy Address |
| Document タブの移動先 | Copy Name |

## ウインドウ内

| 右クリックする場所 | コマンド |
| --- | --- |
| 書類のタイトル、またはツールバーの何もない部分 | Favorites への追加または削除、Save All Open Tabs as a Group、Update Group “名前” with Open Tabs、Compare With（[2つの書類を比較する](compare-documents.md)を参照）、および保存した Tab Groups と Favorites |
| Start 画面の行 | Open、Open in New Tab、Open in New Window、Show in Finder、および Remove または Delete |
| Dock の VectorPDF アイコン | 開いているウインドウとそのタブ（[開いているウインドウを探す](tabs-and-windows.md#find-an-open-window)を参照）、New Window、Open Recent |

コマンドの中には、使用できる場合にのみ表示されるものがあります。たとえば、Save All Open Tabs as a Group には複数のタブが必要です。また、アンカーから開いたウインドウではアンカーのコマンドは使用できません。

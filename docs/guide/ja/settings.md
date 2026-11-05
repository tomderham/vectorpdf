<!-- keywords: 設定, 環境設定, オプション, アップデート, アップデートを確認, ブラウザ, 作成者, 注釈の作成者, ストレージ, ディスク容量, 消去, データを削除, アンインストール, settings, preferences, options, updates, update, check for updates, browser, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->
<!-- source: 95e6c661738e -->

# 設定

VectorPDF > Settings を選択するか、⌘, を押します。

| 設定 | 機能 |
| --- | --- |
| Annotation Author | 注釈と返信に保存される名前です。空の場合は、Mac のユーザ名が使用されます。 |
| Use Agent | macOS 26 以降で、サイドバーに [Ask About This Document](agent.md) タブを表示します。 |
| AI Synthesis Engine | macOS 27 で、[Agent の回答を作成するもの](agent-engines.md)を選択します。 |
| PDF Color | [ページの見た目](pdf-colors.md)を Follow System、Light、Dark、Sepia から設定します。 |
| Open Links In | Web リンクを開くブラウザを選択します。 |
| Ignored Search Patterns | [Smart Search が読み飛ばす](search.md#ignore-clutter-in-the-text)テキストを一覧表示します。 |
| Digital Stamp | [スタンプ](stamps.md)を作成、変更、削除します。 |
| Sync reading positions with iCloud | [ページ、表示倍率、アンカー](reading-positions.md)と[最近の検索](search.md)をほかの Mac でも利用できるようにします。 |
| Storage | VectorPDF のデータが使用している容量を表示し、[消去](#free-up-space-or-remove-data)できるようにします。 |
| Automatically check for updates | 1 日に 1 回程度、GitHub で新しいバージョンを確認します。いつでも確認するには、Check Now をクリックします。 |

## 空き容量を増やす、またはデータを削除する {#free-up-space-or-remove-data}

設定の Storage には、データの種類ごとの使用容量が表示されます:

- **Agent のインデックス:** 書類についての質問に答えるために Agent が作成するもの。削除するには Clear をクリックします。次にその書類で Agent を使うと、再びインデックスが作成されます。VectorPDF は、最も長く使われていないものから削除して 500 MB 未満に保ち、書類がなくなったときはそのインデックスを削除します。
- **読書履歴:** 各書類の最後のページ、表示倍率、アンカー、最近の検索。この Mac と iCloud から消去するには Clear をクリックします。
- **一時ファイル:** 編集、保存、プリント、書き出しの際に作成されるコピーと、ダウンロードしたアップデート。残ったものは、次に VectorPDF を開いたときに削除されます。

VectorPDF が保存したものをすべて削除するには、Remove All VectorPDF Data をクリックします。設定、お気に入り、タブグループ、スタンプ、API キーも削除され、VectorPDF が終了します。書類は変更されません。先に、保存されていない変更がある書類を保存するか閉じてください。

## VectorPDF をアップデートする

VectorPDF > Check for Updates を選択します。新しいバージョンがある場合は、Download をクリックします。ダウンロードが完了したら、**Quit and Open Installer** をクリックしてから、VectorPDF を「アプリケーション」フォルダにドラッグします。

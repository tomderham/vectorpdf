<!-- keywords: 保存, 別名で保存, 未保存, 共有, 変更, 最後に保存した状態に戻す, 復帰, 再読み込み, 変更を破棄, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all -->
<!-- source: 2c2bdeb1617c -->

# 変更を保存する

マークアップ、フォームへの入力、ページの変更、墨消しは、保存するまでファイルに書き込まれません。保存していない変更があるウインドウでは、クローズボタンに点が表示されます。

| 目的 | 操作 |
| --- | --- |
| 保存する | File > Save を選択するか、⌘S を押します |
| 新しい名前でコピーを保存する | File > Save As を選択するか、⇧⌘S を押します |
| パスワードで保護されたコピーを保存する | File > [Save Encrypted with Password](passwords.md) を選択するか、⌥⌘S を押します |

保存していない変更がある書類を閉じると、VectorPDF は変更を保存するかどうかを確認します。

## 変更を破棄する

最後に保存してから行ったすべての変更を破棄するには、File > Revert to Saved を選択します。VectorPDF は確認したあと、最後に保存した状態のファイルを、読んでいたページで開きます。この操作は取り消せません。

書類のサイズを小さくしたコピーを作成するには、[Optimized PDF](export.md#optimized-pdf) を参照してください。

## 書類を共有する

macOS の共有サービスを使用するには File > Share を、ファイルを探すには File > Show in Finder (⇧⌘R) を選択します。Start 画面では、書類を右クリックして Finder に表示できます。

## PDF に保存されないもの

[アンカー](anchors.md)、[読書位置](reading-positions.md)、表示の回転、[OCR](scanned-pages.md) のテキストは VectorPDF に保持され、ファイルには含まれません。

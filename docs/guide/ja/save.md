<!-- keywords: 保存, 別名で保存, 未保存, 共有, 変更, 最後に保存した状態に戻す, 復帰, 再読み込み, 変更を破棄, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all, 自動保存, 復元, 復旧, クラッシュ, 予期せぬ終了, autosave, recover, recovery, crash, quit unexpectedly -->
<!-- source: cdbdeb12d33f -->

# 変更を保存する

マークアップ、フォームへの入力、ページの変更、墨消しは、保存するまでファイルに書き込まれません。保存していない変更があるウインドウでは、クローズボタンに点が表示されます。

| 目的 | 操作 |
| --- | --- |
| 保存する | File > Save を選択するか、⌘S を押します |
| 新しい名前でコピーを保存する | File > Save As を選択するか、⇧⌘S を押します |
| パスワードで保護されたコピーを保存する | File > [Save Encrypted with Password](passwords.md) を選択するか、⌥⌘S を押します |

保存していない変更がある書類を閉じると、VectorPDF は変更を保存するかどうかを確認します。

[デジタル署名](digital-signatures.md)された書類は、署名された部分の後に変更を追加する形で保存されるため、変更が許可されている範囲で署名は有効なままです。

## 変更を破棄する

最後に保存してから行ったすべての変更を破棄するには、File > Revert to Saved を選択します。VectorPDF は確認したあと、最後に保存した状態のファイルを、読んでいたページで開きます。この操作は取り消せません。

書類のサイズを小さくしたコピーを作成するには、[Optimized PDF](export.md#optimized-pdf) を参照してください。

## VectorPDF が予期せず終了した場合 {#if-vectorpdf-quits-unexpectedly}

書類に保存されていない変更があると、VectorPDF はその書類のコピーを Mac に保持し、約 30 秒ごとに更新します。VectorPDF が予期せず終了した場合は、次に開いたときにそのコピーが提示されます:

- **Open Recovered Copy** を選ぶと、各コピーが「(Recovered)」という名前で元の書類の横に保存され、開かれます。元の書類は変更されません。比べてから、残したいほうを残してください。
- **Decide Later** を選ぶと、コピーは保持され、次回また確認されます。
- **Discard Changes** を選ぶと、コピーは削除されます。

コピーは、書類を保存したとき、保存した状態に戻したとき、保存せずに閉じたとき、そして VectorPDF を終了したときに削除されます。パスワードで保護された書類はコピーされません。コピーが暗号化されないためです。

## 書類を共有する

macOS の共有サービスを使用するには File > Share を、ファイルを探すには File > Show in Finder (⇧⌘R) を選択します。Start 画面では、書類を右クリックして Finder に表示できます。

## PDF に保存されないもの

[アンカー](anchors.md)、[読書位置](reading-positions.md)、表示の回転、[OCR](scanned-pages.md) のテキストは VectorPDF に保持され、ファイルには含まれません。ただし、OCR のテキストは [PDF に保存](scanned-pages.md#save-the-recognized-text-in-the-pdf)することもできます。

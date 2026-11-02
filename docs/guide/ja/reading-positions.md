<!-- keywords: 読書位置, 再開, 最後のページ, 同期, 続きから, 他の Mac, reading position, resume, last page, sync, iCloud, Handoff, continue, other Mac -->
<!-- source: 2413ab28f2cf -->

# 読書位置、iCloud、Handoff

## 中断したところから再開する

VectorPDF は、書類ごとに最後のページと表示倍率を記憶し、もう一度開いたときにその状態に戻ります。

## ほかの Mac と同期する

iCloud にサインインしている場合、読書位置と[アンカー](anchors.md)は、同じ Apple Account を使用しているほかの Mac でも利用できます。これは iCloud Drive とクラウドストレージのフォルダにあるファイルで機能し、フォルダの場所が Mac ごとに異なっていても問題ありません。

書類とそのテキストはアップロードされません。この情報を Mac 上だけに保持するには、[Settings](settings.md) で **Sync reading positions with iCloud** をオフにします。オフにすると、iCloud 上の VectorPDF の項目も削除されます。

> **注記:** iCloud 同期は VectorPDF のビルド方法によって異なるため、自分でビルドした VectorPDF では使用できない場合があります。

## Handoff

Handoff がオンの場合、別の Mac で続きを読むことができます。VectorPDF は表示中の書類とページを提示し、その Mac でファイルが利用できる場合は開きます。

Handoff のオン/オフを切り替えるには、システム設定の「AirDrop と Handoff」の設定を確認してください。

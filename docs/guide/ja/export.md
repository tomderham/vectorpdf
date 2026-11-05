<!-- keywords: 書き出し, 書き出す, 変換, プレーンテキスト, テキスト, フラット化, 注釈の概要, 最適化, ファイルサイズを縮小, 圧縮, 小さく, イメージ, フォント, アウトライン, テキストのアウトライン化, プロッタ, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF, optimize, optimized, reduce file size, compress, smaller, downsample, images, fonts, subset, outlines, text to outlines, plotter -->
<!-- source: 0e99b5515751 -->

# 他のフォーマットに書き出す

書類全体を書き出すには、File > Export Document As を選択してから、Plain Text、Word Document、Scalable Vector Graphics、Flattened PDF、または Optimized PDF を選択します。注釈の概要と測定値には、それぞれ専用のコマンドがあります。

## Plain Text

書類のテキストを `.txt` ファイルとして保存します。

## Word Document

Word などのアプリで編集できる `.docx` ファイルを保存します。複雑なページレイアウトは、PDF と見た目が異なる場合があります。

## SVG

各ページを Scalable Vector Graphics ファイルとして保存します。テキストはベクトルパスになるため、PDF とまったく同じ見た目になります。複数ページの書類は、ページごとに 1 つのファイルが入ったフォルダとして保存されます。

## Flattened PDF {#flattened-pdf}

注釈とフォームフィールドをページの一部にした PDF を保存します。保存後は変更できません。保存ダイアログで、フラット化する対象を選択します:

- **Flatten annotations and markups**
- **Flatten form fields (make static)**

> **注記:** フラット化しても、下にある内容は削除されません。内容を削除するには、[墨消し](redact.md)を使用してください。

## Optimized PDF {#optimized-pdf}

PDF のサイズを小さくしたコピーを保存します。まだ保存していない変更も含まれます。開いている書類は変更されません。書類で使われなくなったデータは削除され、重複は統合され、すべてが圧縮されます。保存ダイアログでは、次の項目も選択できます:

- **Keep only the characters each font uses:** 埋め込みフォントのうち、書類で使われていない部分を削除します。デフォルトでオンです。
- **Images:** イメージをそのままにするか、300 dpi（印刷用）または 150 dpi（画面での閲覧用）に縮小します。それより解像度の高いイメージだけが縮小されます。写真は JPEG で保存され、図やスクリーンショットは劣化しません。白黒のスキャンは変更されません。
- **Convert text to outlines:** すべての文字を図形として描画するため、書類のフォントを持たないプロッタ、カッター、印刷システムでも同じように表示されます。コピーのテキストは選択、検索、コピーできなくなります。

コピーがどれだけ小さくなるかは書類によって異なります。イメージを縮小すると、スキャンや写真が最も小さくなります。

## 注釈の概要

File > Export Annotations Summary (⇧⌘E) を選択すると、書類の注釈の一覧を、ほかのアプリの注釈も含めて、作成者、ステータス、返信とともに保存できます。デフォルトでは Markdown ファイルになります。スプレッドシートとして保存するには、ファイルの拡張子を `.csv` にします。

## 測定値

測定値を書き出すには、[拾い出し表](takeoff.md)を使用します。

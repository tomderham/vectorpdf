<!-- keywords: 書き出し, 書き出す, 変換, プレーンテキスト, テキスト, フラット化, 注釈の概要, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF -->
<!-- source: 6298933ea76c -->

# 他のフォーマットに書き出す

File > Export Document As を選択してから、フォーマットを選択します。

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

## 注釈の概要

File > Export Annotations Summary (⇧⌘E) を選択すると、注釈の一覧を保存できます。デフォルトでは Markdown ファイルになります。スプレッドシートとして保存するには、ファイルの拡張子を `.csv` にします。

## 測定値

測定値を書き出すには、[拾い出し表](takeoff.md)を使用します。

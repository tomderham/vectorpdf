<!-- keywords: 拡大, 縮小, ズーム, 幅に合わせる, ウインドウに合わせる, 実際のサイズ, 回転, 2 ページ, 見開き, 本, レイアウト, 表示, 横, 横スクロール, 横並び, 楽譜, スコア, ワイド画面, ページめくり, ペダル, zoom, magnify, fit width, fit window, actual size, rotate, rotation, two pages, two-page, spread, book, layout, view, horizontal, horizontal scrolling, side by side, sheet music, score, widescreen, page turner, pedal -->
<!-- source: 2988071d44f3 -->

# 拡大/縮小、回転、ページレイアウト

## 拡大/縮小

| 目的 | 操作 |
| --- | --- |
| 拡大または縮小する | ⌘+ または ⌘− を押すか、ツールバーの + または − をクリックするか、トラックパッドでピンチします |
| 正確な倍率を設定する | ツールバーのパーセント表示をクリックし、10〜1000 の値を入力して、Return キーを押します |
| ページを実際のサイズで表示する | View > Actual Size (100%) を選択するか、⌘1 を押します |
| ページの幅に合わせる | View > Zoom to Fit Width を選択するか、⌘9 を押します |
| ページ全体を表示する | View > Zoom to Fit Window を選択するか、⌥⌘0 を押します |

Zoom In コマンドと Zoom Out コマンドは 25%〜400% の範囲で機能します。この範囲を超えるには、パーセントを入力します。

VectorPDF は、画像を拡大するのではなくページを再描画するため、どの倍率でもページは鮮明なままです。

## 100% の意味

View > Define 100% Scale As を選択してから、次のいずれかを選択します:

- **Size on Screen Equals Size on Printout:** 100% のページが、プリントしたときとほぼ同じサイズで表示されます。
- **1 Point Equals 1 Screen Point:** PDF の 1 ポイントが、ディスプレイの 1 ポイントを占めます。

## 表示を回転する {#rotate-the-view}

ツールバーの Rotate Left または Rotate Right をクリックします。この操作は画面上の書類の見え方だけを変更するもので、保存されません。PDF のページ自体を回転するには、[ページを並べ替える](pages.md)を参照してください。

## Two-Page Mode

ツールバーの Two-Page Mode をクリックするか、View > Two Pages (⌥⌘2) を選択します。開いた本のように、表紙を単独にしてページが 2 ページずつ表示され、見開きがウインドウに合わせて拡大/縮小されます。元に戻すには、もう一度ボタンをクリックするか、View > Single Page を選択します。

## Horizontal Scrolling

ツールバーの Horizontal Scrolling をクリックするか、View > Horizontal Scrolling を選択すると、ページが縦ではなく左から右に並びます。ページがウインドウの高さに収まるように拡大/縮小され、ウインドウの幅に収まるだけのページが表示されます。ワイドなディスプレイや縮小表示では、より多くのページが表示されます。楽譜を見るときに便利です。

トラックパッドで左右にスワイプすると、ページに沿ってスクロールします。ページがウインドウの高さに収まっていれば、マウスのホイールでも横にスクロールします。Right Arrow と Left Arrow で、次または前のページをウインドウの左端に移動します。Space と Page Down では 1 画面分進み、全体が見えていなかった最初のページが先頭に来ます。⇧Space と Page Up では 1 画面分戻ります。Bluetooth のページめくり器やフットペダルは通常これらのキーを送るため、同じように使えます。

Horizontal Scrolling と Two-Page Mode は互いに切り替わります。一方をオンにすると、もう一方はオフになります。Horizontal Scrolling がオンのとき、Zoom to Fit Window ではページの高さに合わせます。

元に戻すには、もう一度ボタンをクリックするか、View > Vertical Scrolling を選択します。注釈はどちらのレイアウトでも表示され、編集できます。Compare Documents は常に縦にスクロールします。

> **注記:** 表示を回転しているとき、Two-Page Mode のとき、横スクロールのときも、テキストの選択、リンク、検索、マークアップツールと測定ツール、フォームへの入力を使用できます。追加したものはページ自体に配置されるため、表示の回転を戻しても位置は変わりません。

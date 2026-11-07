<!-- keywords: LaTeX, TeX, SyncTeX, 順方向検索, 逆方向検索, ソース, ソースコード, エディタ, ソースへ移動, LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->
<!-- source: a865c846e0d7 -->

# LaTeX ソースと PDF の間を移動する

LaTeX で書いている場合、VectorPDF では、PDF のある位置からそれを生成したソースの行へ、またソースの行から PDF 内でそれが生成した位置へ移動できます。これには SyncTeX を使います。SyncTeX は、TeX が `-synctex=1` を付けてビルドすると有効になります。ほとんどの LaTeX エディタはこの方法でビルドします。

SyncTeX は、PDF と同じ名前の SyncTeX ファイルがその横にある PDF で使えます（`paper.pdf` と `paper.synctex.gz`）。フォルダ内のほかの PDF には影響しません。

## エディタを選択する

1. VectorPDF > Settings を選択し、LaTeX (SyncTeX) の横にある Set Up… をクリックします。
2. Source Editor からエディタを選択します：Visual Studio Code、VSCodium、Cursor、Zed、Sublime Text、BBEdit、TextMate、MacVim、Emacs、TeXstudio。
3. 使っているエディタが一覧にない場合は、Other を選択し、ファイルを特定の行で開くコマンドを入力します。ファイルには `%file`、行には `%line` と書きます（例：`myeditor +%line %file`）。

エディタの下に、Settings が見つけたプログラムが表示されます。プログラムが見つからないと表示された場合は、エディタのコマンドラインツールをインストールするか、Other を選択してプログラムのフルパスを指定してください。

## PDF からソースへ移動する

PDF のある位置を ⇧⌘ を押しながらクリックします。エディタで、その位置を生成した行のソースファイルが開きます。

右クリックして **Show in Editor** を選択することもできます。SyncTeX ファイルがある PDF では、メニューの先頭にあります。

## ソースから PDF へ移動する

エディタは、VectorPDF に付属する `displayline` を実行して、VectorPDF に行を表示するよう依頼します：

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

VectorPDF は PDF を前面に表示し（開いていない場合は開き）、その行を少しの間赤く強調表示します。行がすでに画面に表示されている場合はスクロールしません。LINE の前に `-g` を付けると、VectorPDF はエディタの背面に表示されたままになります。

`displayline` は Skim のものと同じ引数を受け付けます。エディタに Skim 用の設定がある場合は、代わりに VectorPDF の `displayline` を指定してください。

### Visual Studio Code

LaTeX Workshop 拡張機能を使っている場合は、設定に次の行を追加します。設定はコマンドパレットで Preferences: Open User Settings (JSON) を選択すると開きます。

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

その後、Visual Studio Code で ⌥⌘B を押すとビルド、⌥⌘V を押すと VectorPDF で PDF を開き、⌥⌘J を押すと現在の行を表示します。最後の設定を追加すると、ビルドするたびに VectorPDF がその行を表示します。

## 書いている間

エディタが PDF をビルドし直すと、VectorPDF は表示位置、拡大率、回転、ページレイアウトを保ったまま再読み込みします。ファイルの書き込みがまだ終わっていない場合は、終わるまで待ちます。

## うまくいかない場合

- **メニューに Show in Editor がない：** PDF に SyncTeX ファイルがありません。SyncTeX を有効にしてビルドし、SyncTeX ファイルを PDF の横、またはその横にある build や out という名前のフォルダに置いてください。
- **No Source Here：** その位置（余白や画像など）に対応するソースの行がありません。テキストをクリックしてください。
- **VectorPDF で何も起こらない：** エディタが VectorPDF の `displayline` を実行していること、そしてソースを最後に変更したあとに SyncTeX を有効にして PDF をビルドしたことを確認してください。
- **TeX をインストールしたのにエディタが見つけられない：** エディタを終了して、もう一度開いてください。

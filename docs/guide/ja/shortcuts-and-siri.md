<!-- keywords: ショートカット, Siri, Spotlight, 自動化, アクション, 質問, 検索, ページの抽出, 書類を開く, ワークフロー, Shortcuts, automation, action, actions, App Intents, ask, search, extract pages, open document, workflow -->
<!-- source: 0598b760c342 -->

# ショートカットと Siri で VectorPDF を使う

VectorPDF はショートカット App にアクションを追加します。独自のショートカットで使用したり、Spotlight や Siri から使用したりできます。

| アクション | 機能 |
| --- | --- |
| Ask About Document | [Agent](agent.md) に質問し、ページの引用付きで回答を返します |
| Search Document | 検索フィールドと同じようにテキストを検索し、一致した箇所をページ番号とともに返します |
| Extract Pages | PDF の一部のページ（`1-3, 5` など）から新しい PDF を作成します |
| Open Document | VectorPDF で書類を開きます。ページを指定すると、そのページで開きます |

Ask、Search、Extract Pages で書類を選択しない場合、アクションは VectorPDF の最前面の書類を使用します。

## ショートカットでアクションを使う

1. ショートカット App を開き、ショートカットを作成するか開きます。
2. アクションの一覧で VectorPDF を検索し、アクションをショートカットにドラッグします。
3. アクションの項目を入力します。ファイルを取得するアクションなど、ショートカットの前の手順のファイルを使うには、Document をクリックしてそのファイルを選択します。

各アクションは、返したもの（回答、一致した箇所の一覧、または新しい PDF）を次に渡します。PDF を作成する、メモに追加する、メッセージを送信するなど、ほかのアクションに送ることができます。

VectorPDF のアクションが表示されない場合は、VectorPDF を一度開いてから、ショートカットを終了して開き直してください。

## Siri に頼む

次のフレーズを Siri に話すか入力できます。質問など、ほかに必要なことは Siri が尋ねます。VectorPDF はまだ翻訳されていないため、フレーズは英語です。Siri の言語が英語のときに使用できます:

- "Ask VectorPDF about this document"
- "Search this document in VectorPDF"
- "Extract pages in VectorPDF"
- "Open a document in VectorPDF"

Spotlight でアクションの名前を入力して見つけることもできます。

## 各アクションについて

- **Ask About Document** は、書類が開いていない場合、作業中のウインドウの後ろで VectorPDF に書類を開きます。質問と回答は書類の Ask About This Document タブにも表示されるため、出典を読んだり続けて質問したりできます。Agent をオンにする必要があり、[Agent の回答方法を選択する](agent-engines.md)で選択したエンジンが回答します。回答を生成できない場合は、最も一致する箇所を返します。
- **Search Document** は、Smart Search と [Ignored Search Patterns](search.md#ignore-clutter-in-the-text) を使用し、オンにした場合は Match Case と Whole Words も使用します。最大 100 件の一致を返し、合計件数も伝えます。開いている書類は、保存していない変更を含め、表示しているレイヤーだけを対象に VectorPDF での状態のまま検索します。ほかの書類は開かずに検索します。
- **Extract Pages** には、ページと範囲をカンマで区切って指定します。`5-` のような範囲は最後のページまで、`3-1` はページを逆順で指定します。最後に保存された状態のファイルを読み取り、ファイルは変更しません。新しい PDF の名前は、書類とページから付けられます（「Report (Pages 1-3, 5).pdf」など）。
- **Open Document** は、書類がすでに開いている場合、そのタブを最前面に表示します。

パスワードで保護された書類を Search Document で検索するには、その書類を VectorPDF で開いてパスワードを入力しておく必要があります。Extract Pages では、パスワードで保護された書類は使用できません。

> **注記:** アクションが返したものはショートカットまたは Siri に渡され、そこからショートカットの次の手順に渡されます。Ask About Document が送信するのは、VectorPDF で質問したときに Agent が送信するものだけです。[プライバシー](privacy.md)を参照してください。

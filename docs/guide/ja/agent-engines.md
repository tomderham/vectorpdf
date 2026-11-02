<!-- keywords: Agent, AI, エンジン, デバイス上, オンラインモデル, APIキー, API キー, 回答, 合成, Agent, AI, engine, on-device, Private Cloud Compute, online model, API key, OpenAI, Gemini, OpenRouter -->
<!-- source: dbbd02de21b5 -->

# Agent の回答方法を選択する

関連する箇所の検索は、常に Mac 上で行われます。回答を作成するものは、VectorPDF > Settings > AI Synthesis Engine で選択できます。この設定には macOS 27 が必要です。

| エンジン | 仕組み | Mac の外に送信されるもの |
| --- | --- | --- |
| On-Device | Mac 上の Apple Intelligence | なし |
| Private Cloud Compute | Apple のサーバ。より長く詳しい回答に使用されます | 質問と、回答に使用する箇所。Apple の Private Cloud Compute に送信されます |
| Online Model (your API key) | 選択したサービス。料金はそのサービスの自分のアカウントに請求されます | 質問、該当箇所 (短い書類の場合はテキスト全体)、それまでの会話 |

macOS 26 では、Agent はデバイス上で回答します。

Private Cloud Compute は、そのための署名がされた VectorPDF にのみ表示されます。GitHub からダウンロードしたバージョンは、デバイス上で回答します。

## オンラインモデルを使用する

1. Settings で、AI Synthesis Engine を Online Model に設定します。
2. サービスを OpenAI、Google Gemini、OpenRouter から選択します。
3. API キーを入力します。各サービスの API キーを取得するためのリンクが用意されています。キーはログインキーチェーンに保存されます。
4. モデルを選択します。

サービスが回答できない場合は、VectorPDF がデバイス上で回答します。

> **警告:** 送信する内容には、サービスのプライバシーポリシーと利用規約が適用されます。無料の Gemini キーでは、送信した内容が Google の製品改善に使用されたり、担当者に確認されたりすることがあるため、機密性の高い書類は送信しないでください。[プライバシー](privacy.md)を参照してください。

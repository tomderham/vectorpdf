# Choose how the Agent answers

The search for relevant passages always happens on your Mac. You can choose what writes the answer in VectorPDF > Settings > AI Synthesis Engine. This setting needs macOS 27.

| Engine | How it works | What leaves your Mac |
| --- | --- | --- |
| On-Device | Apple Intelligence on your Mac | Nothing |
| Private Cloud Compute | Apple's servers, for longer and more detailed answers | Your question and the passages used, which go to Apple's Private Cloud Compute |
| Online Model (your API key) | A service you choose, billed to your account with it | Your question, the passages (or the whole text of a short document) and the earlier conversation |

On macOS 26, the Agent answers on-device.

Private Cloud Compute appears only in copies of VectorPDF that are signed for it. The version you download from GitHub answers on-device.

## Use an online model

1. In Settings, set AI Synthesis Engine to Online Model.
2. Choose a service: OpenAI, Google Gemini or OpenRouter.
3. Enter your API key. There's a link to get one from each service. The key is stored in your login keychain.
4. Choose a model.

If the service can't answer, VectorPDF answers on-device.

> **Warning:** The service's privacy policy and terms apply to what you send. On free Gemini keys, Google may use what you send to improve its products, and people may review it, so don't send confidential documents. See [Privacy](privacy.md).

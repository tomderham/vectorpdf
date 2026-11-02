<!-- keywords: 에이전트, 인공지능, 엔진, 기기 내, 온라인 모델, API 키, Agent, AI, engine, on-device, Private Cloud Compute, online model, API key, OpenAI, Gemini, OpenRouter -->
<!-- source: dbbd02de21b5 -->

# Agent의 답변 방식 선택하기

관련 구절 검색은 항상 Mac에서 이루어집니다. 답변을 작성하는 주체는 VectorPDF > Settings > AI Synthesis Engine에서 선택할 수 있습니다. 이 설정에는 macOS 27이 필요합니다.

| 엔진 | 작동 방식 | Mac 밖으로 전송되는 항목 |
| --- | --- | --- |
| On-Device | Mac의 Apple Intelligence | 없음 |
| Private Cloud Compute | 더 길고 자세한 답변을 위한 Apple 서버 | 질문과 사용된 구절이 Apple의 Private Cloud Compute로 전송됩니다. |
| Online Model (your API key) | 사용자가 선택한 서비스. 해당 서비스의 계정으로 요금이 청구됩니다. | 질문, 구절(또는 짧은 문서의 경우 전체 텍스트) 및 이전 대화 |

macOS 26에서는 Agent가 기기 내에서 답변합니다.

Private Cloud Compute는 이를 위해 서명된 VectorPDF 사본에서만 나타납니다. GitHub에서 다운로드한 버전은 기기 내에서 답변합니다.

## 온라인 모델 사용하기

1. Settings에서 AI Synthesis Engine을 Online Model로 설정합니다.
2. OpenAI, Google Gemini 또는 OpenRouter 중에서 서비스를 선택합니다.
3. API 키를 입력합니다. 각 서비스에서 키를 받을 수 있는 링크가 제공됩니다. 키는 로그인 키체인에 저장됩니다.
4. 모델을 선택합니다.

서비스가 응답할 수 없으면 VectorPDF가 기기 내에서 답변합니다.

> **경고:** 전송하는 내용에는 해당 서비스의 개인정보 처리방침과 약관이 적용됩니다. 무료 Gemini 키를 사용하는 경우 Google이 전송된 내용을 제품 개선에 사용할 수 있고 사람이 검토할 수도 있으므로 기밀 문서를 보내지 마십시오. [개인정보 보호](privacy.md)를 참조하십시오.

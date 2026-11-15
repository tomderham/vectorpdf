<!-- keywords: 단축어, Siri, Spotlight, 자동화, 동작, 질문, 검색, 페이지 추출, 문서 열기, 워크플로, Shortcuts, automation, action, actions, App Intents, ask, search, extract pages, open document, workflow -->
<!-- source: 0598b760c342 -->

# 단축어 및 Siri와 함께 VectorPDF 사용하기

VectorPDF는 단축어 앱에 동작을 추가하므로, 직접 만든 단축어에서 사용하거나 Spotlight와 Siri에서 사용할 수 있습니다.

| 동작 | 기능 |
| --- | --- |
| Ask About Document | [Agent](agent.md)에게 질문하고 페이지 인용과 함께 답변을 반환합니다 |
| Search Document | 검색 필드처럼 텍스트를 찾고, 일치하는 항목을 페이지 번호와 함께 반환합니다 |
| Extract Pages | PDF의 일부 페이지(`1-3, 5` 등)로 새 PDF를 만듭니다 |
| Open Document | VectorPDF에서 문서를 열며, 페이지를 지정하면 해당 페이지에서 엽니다 |

Ask, Search, Extract Pages에서 문서를 선택하지 않으면 동작은 VectorPDF의 맨 앞에 있는 문서를 사용합니다.

## 단축어에서 동작 사용하기

1. 단축어 앱을 열고 단축어를 만들거나 엽니다.
2. 동작 목록에서 VectorPDF를 검색한 다음, 동작을 단축어로 드래그합니다.
3. 동작을 채웁니다. 파일을 가져오는 동작처럼 단축어의 이전 단계에서 나온 파일을 사용하려면 Document를 클릭하고 해당 파일을 선택합니다.

각 동작은 반환한 결과(답변, 일치 항목 목록 또는 새 PDF)를 다음 단계로 넘깁니다. 이를 PDF를 만들거나, 메모에 추가하거나, 메시지를 보내는 동작 등 다른 동작으로 보낼 수 있습니다.

VectorPDF 동작이 나타나지 않으면 VectorPDF를 한 번 연 다음, 단축어를 종료했다가 다시 엽니다.

## Siri에게 요청하기

Siri에게 다음 문구를 말하거나 입력할 수 있습니다. 질문 등 필요한 것이 더 있으면 Siri가 물어봅니다. VectorPDF는 아직 번역되지 않았으므로 문구는 영어이며, Siri 언어가 영어일 때 작동합니다.

- "Ask VectorPDF about this document"
- "Search this document in VectorPDF"
- "Extract pages in VectorPDF"
- "Open a document in VectorPDF"

Spotlight에서 동작 이름을 입력하여 찾을 수도 있습니다.

## 각 동작에 관하여

- **Ask About Document**는 문서가 열려 있지 않으면 작업 중인 윈도우 뒤에서 VectorPDF로 문서를 엽니다. 질문과 답변은 문서의 Ask About This Document 탭에도 나타나므로 출처를 읽고 후속 질문을 할 수 있습니다. Agent가 켜져 있어야 하며, [Agent의 답변 방식 선택하기](agent-engines.md)에서 선택한 엔진으로 답변합니다. 답변을 생성할 수 없으면 가장 잘 일치하는 구절을 반환합니다.
- **Search Document**는 Smart Search와 [Ignored Search Patterns](search.md#ignore-clutter-in-the-text)를 사용하며, 켠 경우 Match Case와 Whole Words도 사용합니다. 최대 100개의 일치 항목을 반환하고 전체 개수를 알려 줍니다. 열려 있는 문서는 저장하지 않은 변경 사항을 포함하여 표시된 레이어만 대상으로 VectorPDF에서의 상태 그대로 검색하며, 다른 문서는 열지 않고 검색합니다.
- **Extract Pages**에는 페이지와 범위를 쉼표로 구분하여 입력합니다. `5-` 같은 범위는 마지막 페이지까지이며, `3-1`은 페이지를 역순으로 가져옵니다. 마지막으로 저장된 상태의 파일을 읽으며 파일을 변경하지 않습니다. 새 PDF의 이름은 문서와 페이지를 따서 붙습니다(예: "Report (Pages 1-3, 5).pdf").
- **Open Document**는 문서가 이미 열려 있으면 해당 탭을 앞으로 가져옵니다.

암호로 보호된 문서는 VectorPDF에서 열고 암호를 입력해야 Search Document로 검색할 수 있습니다. Extract Pages는 암호로 보호된 문서를 사용할 수 없습니다.

> **참고:** 동작이 반환한 결과는 단축어 또는 Siri로 전달되고, 거기서 단축어의 다음 단계로 넘어갑니다. Ask About Document는 VectorPDF에서 질문할 때 Agent가 보내는 것만 전송합니다. [개인정보 보호](privacy.md)를 참고하십시오.

<!-- keywords: 윈도우, 창, 도구 막대, 툴바, 사이드바, 탭, 시작 화면, 인터페이스, 페이지 표시기, 컨트롤, 첨부 파일, window, toolbar, toolbars, sidebar, tabs, start screen, interface, page indicator, controls, attachments, 상태 막대, Inspector, status bar -->
<!-- source: cce7c7e75b8e -->

# VectorPDF 윈도우

각 VectorPDF 윈도우는 도구 막대, 사이드바, 문서로 이루어져 있습니다. 윈도우 하나에 여러 문서를 [탭](tabs-and-windows.md)으로 열어 둘 수 있습니다.

## 도구 막대

| 컨트롤 | 기능 |
| --- | --- |
| 문서 제목 | 문서의 이름을 표시합니다. 오른쪽 클릭하면 Favorites 및 Tab Groups 명령을 사용할 수 있습니다. |
| Zoom | − 및 + 버튼으로 확대/축소 비율을 단계별로 변경합니다. 퍼센트 값을 클릭하면 원하는 값을 입력할 수 있습니다. |
| Rotate Left 및 Rotate Right | 보기를 회전합니다. 저장된 PDF는 변경되지 않습니다. |
| Two-Page Mode | 펼친 책처럼 페이지를 나란히 표시합니다. |
| Markup Toolbar | [마크업 도구](text-markup.md)를 표시합니다. |
| Measurement Toolbar | [측정 도구](measure.md)를 표시합니다. |
| Page | 화살표를 클릭하면 한 페이지씩 이동합니다. 페이지 번호를 클릭하면 원하는 페이지를 입력할 수 있습니다. |

이러한 컨트롤에 관한 자세한 내용은 [확대/축소, 회전 및 페이지 레이아웃](zoom-and-layout.md)을 참조하십시오.

## 사이드바

사이드바 상단의 탭으로 다음 항목 사이를 전환합니다.

- **Outline & Thumbnails:** [목차 또는 각 페이지의 축소판](outline-and-thumbnails.md).
- **Search:** [현재 문서의 검색 결과](search.md).
- **Anchors:** [저장한 위치](anchors.md).
- **Document:** 문서의 페이지 외에 담긴 내용으로, [레이어](layers.md), [첨부 파일](attachments.md), [디지털 서명](digital-signatures.md) 및 설정에서 켠 경우 [양식 필드, 링크 및 대상](document-tab.md)입니다. 탭 상단의 메뉴에서 무엇을 볼지 선택합니다. 이 탭은 문서에 이 중 하나 이상이 있을 때만 나타납니다.
- **Comments:** [모든 주석과 그 답글 및 상태](draw-and-notes.md#see-all-annotations).
- **Ask About This Document:** [Agent](agent.md). 이 탭은 macOS 26 이상에서 나타나며, Settings에서 [Use Agent](settings.md)를 끈 경우에는 나타나지 않습니다.

도구 막대의 사이드바 버튼을 사용하여 사이드바를 보거나 가립니다. VectorPDF는 문서마다 사이드바를 보았는지 가렸는지 기억합니다. 문서를 처음 열 때는 문서가 한두 페이지뿐이고 사이드바에 표시할 것(개요, 레이어, 주석, 첨부 파일)이 없는 경우를 제외하면 사이드바가 표시됩니다. 첨부 파일이나 레이어가 있는 짧은 문서는 그것이 보이는 Document 탭으로 열리고, 주석이 있는 짧은 문서는 Comments 탭으로 열립니다.

## 추가 도구 막대

필요할 때 기본 도구 막대 아래에 나타나는 도구 막대가 세 개 있습니다. View 메뉴에서 선택합니다.

- **Markup** (⇧⌘A)에는 [주석 도구](text-markup.md)가 있습니다.
- **Measurement** (⇧⌘M)에는 [측정 도구](measure.md)가 있습니다.
- **Redact** (⌥⌘R)에는 [가림 처리 도구](redact.md)가 있습니다.

View 메뉴에서는 페이지 아래의 상태 막대, 눈금자, 격자, 페이지 옆의 Inspector, 모서리의 탐색기도 표시할 수 있습니다. [눈금자, 상태 막대 및 Inspector](rulers-and-inspector.md)를 참고하십시오.

## 오른쪽 클릭 메뉴

많은 명령은 문서, 사이드바 또는 도구 막대를 오른쪽 클릭하거나 Control-클릭할 때 나타나는 메뉴에서도 사용할 수 있습니다. [오른쪽 클릭 메뉴](right-click-menus.md)를 참조하십시오.

## 페이지 표시기

페이지를 넘기면 작은 페이지 표시기가 문서 위에 잠시 나타나며, 여기에는 이전 페이지와 다음 페이지로 이동하는 화살표가 있습니다. Measurement 도구 막대가 표시되어 있는 동안에는 해당 페이지의 도면 축척도 표시됩니다.

## Start 화면

빈 윈도우나 탭에는 Start 화면이 표시되며, 드롭 영역 아래에 Tab Groups, Favorites, Recent Documents가 나타납니다. 행을 클릭하면 해당 항목이 열립니다. 행 위에 포인터를 올려놓고 ••• 버튼을 클릭하거나 행을 오른쪽 클릭하면 새로운 탭이나 윈도우에서 열기, Finder에서 보기, 제거 작업을 할 수 있습니다.

Start 화면에는 Tab Groups가 최대 3개, Favorites가 최대 5개까지 표시됩니다. Favorites 메뉴에는 모두 표시됩니다.

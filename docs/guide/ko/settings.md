<!-- keywords: 설정, 환경설정, 옵션, 업데이트, 업데이트 확인, 브라우저, 작성자, 주석 작성자, 저장 공간, 디스크 공간, 지우기, 데이터 제거, 데이터 삭제, 제거, settings, preferences, options, updates, update, check for updates, browser, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->
<!-- source: 91c5b0e9ab3d -->

# 설정

VectorPDF > Settings를 선택하거나 ⌘, 키를 누릅니다.

| 설정 | 기능 |
| --- | --- |
| Annotation Author | 주석과 답글에 저장되는 이름입니다. 비어 있으면 VectorPDF는 Mac 사용자 이름을 사용합니다. |
| Use Agent | macOS 26 이상에서 사이드바에 [Ask About This Document](agent.md) 탭을 표시합니다. |
| AI Synthesis Engine | macOS 27에서 [Agent의 답변을 작성하는 주체](agent-engines.md)를 선택합니다. |
| PDF Color | [페이지가 표시되는 방식](pdf-colors.md)을 Follow System, Light, Dark 또는 Sepia로 설정합니다. |
| Open Links In | 웹 링크에 사용할 브라우저를 선택합니다. |
| LaTeX (SyncTeX) | PDF를 ⇧⌘을 누른 채 클릭할 때 [LaTeX 소스](latex.md)를 여는 편집기를 선택합니다. |
| Ignored Search Patterns | [Smart Search가 건너뛰는](search.md#ignore-clutter-in-the-text) 텍스트를 나열합니다. |
| Digital Stamp | [스탬프](stamps.md)를 만들거나 변경하거나 삭제합니다. |
| Sync reading positions with iCloud | [페이지, 확대/축소, 앵커](reading-positions.md)와 [최근 검색](search.md)을 다른 Mac에서도 유지합니다. |
| Storage | VectorPDF 데이터가 차지하는 공간을 표시하고 [지울 수 있게](#free-up-space-or-remove-data) 합니다. |
| Automatically check for updates | 약 하루에 한 번 GitHub에서 새로운 버전을 확인합니다. 언제든지 확인하려면 Check Now를 클릭합니다. |

## 공간 확보 또는 데이터 제거 {#free-up-space-or-remove-data}

설정의 Storage 아래에 데이터 종류별로 차지하는 공간이 표시됩니다.

- **Agent 색인:** Agent가 문서에 관한 질문에 답하기 위해 만드는 것입니다. 삭제하려면 Clear를 클릭합니다. 다음에 그 문서에서 Agent를 사용하면 다시 색인됩니다. VectorPDF는 가장 오랫동안 사용하지 않은 것부터 삭제하여 500MB 미만으로 유지하며, 문서가 없어지면 해당 색인을 삭제합니다.
- **읽기 기록:** 각 문서의 마지막 페이지, 확대/축소, 앵커 및 최근 검색입니다. 이 Mac과 iCloud에서 지우려면 Clear를 클릭합니다.
- **임시 파일:** 편집, 저장, 프린트 또는 내보내기 중에 만들어진 사본과 다운로드한 업데이트입니다. 남은 파일은 다음에 VectorPDF를 열 때 삭제됩니다.

VectorPDF가 저장한 모든 것을 제거하려면 Remove All VectorPDF Data를 클릭합니다. 설정, 즐겨찾기, 탭 그룹, 스탬프 및 API 키도 제거된 후 VectorPDF가 종료됩니다. 문서는 변경되지 않습니다. 먼저 저장하지 않은 변경 사항이 있는 문서를 저장하거나 닫으십시오.

## VectorPDF 업데이트하기

VectorPDF > Check for Updates를 선택합니다. 새로운 버전이 있으면 Download를 클릭합니다. 다운로드가 완료되면 **Quit and Open Installer**를 클릭한 다음 VectorPDF를 응용 프로그램 폴더로 드래그합니다.

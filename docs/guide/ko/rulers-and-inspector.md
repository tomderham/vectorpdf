<!-- keywords: 상태 막대, 포인터 위치, 좌표, 페이지 크기, 용지 크기, 눈금자, 안내선, 격자, 맞춤, 단위, 밀리미터, 인치, 포인트, Inspector, 서체, 서체 크기, 색상, 이미지 해상도, 탐색기, 단어 수, 문자 수, status bar, pointer position, coordinates, page size, paper size, A4, Letter, ARCH, rulers, guides, grid, snap, units, millimeters, inches, points, font, font size, color, image resolution, dpi, ppi, line width, navigator, pan and zoom, word count, character count -->
<!-- source: f1f2dd215a95 -->

# 눈금자, 상태 막대 및 Inspector

이 기능들은 페이지에서 무엇이 어디에 있는지, 무엇으로 이루어져 있는지 보여 줍니다. 읽기 화면을 깔끔하게 유지하기 위해 View 메뉴에서 켜기 전까지는 꺼져 있습니다.

## 상태 막대

View > Show Status Bar(⌘/)를 선택하면 페이지 아래에 띠가 표시됩니다. 다음 정보가 표시됩니다.

- 페이지의 왼쪽 상단 모서리를 기준으로 한 **포인터의 위치**. [도면 축척](drawing-scale.md)이 있는 페이지에서는 그 위치를 실제 단위로도 보여 줍니다.
- 포인터 아래 페이지 또는 현재 페이지의 **페이지 크기**와, 일치하는 경우 용지 크기 이름: A0~A6, B3~B5, Letter, Legal, Tabloid, ANSI C~E, ARCH A~E. 도면 세트는 시트 크기가 섞여 있는 경우가 많으므로 페이지를 옮겨 다니면 표시가 바뀝니다.
- **그리는 중인 측정:** 길이, 각도, 가로(ΔX)와 세로(ΔY)로 뻗은 거리, 지금까지의 둘레 길이와 마지막 선분, 지금까지의 면적과 그 둘레. [길이, 면적 및 각도 측정하기](measure.md)를 참고하십시오.
- 단어 및 문자 수로 나타낸 **텍스트 선택 영역의 크기**.

상태 막대 오른쪽의 메뉴에서 단위(Millimeters, Inches 또는 Points)를 선택합니다. 눈금자, 격자, Inspector도 같은 단위를 사용합니다.

## 눈금자와 안내선

View > Rulers and Grid > Show Rulers(⌘R)를 선택하면 페이지 위쪽과 왼쪽에 눈금자가 표시됩니다. 눈금자는 포인터 아래 페이지를 왼쪽 상단 모서리부터 재며, 각 눈금자의 선이 포인터의 위치를 보여 줍니다.

| 작업 | 방법 |
| --- | --- |
| 안내선 추가하기 | 눈금자에서 페이지로 드래그합니다 |
| 안내선 이동하기 | 안내선을 드래그합니다 |
| 안내선 제거하기 | 안내선을 페이지 밖으로 드래그합니다 |
| 모든 안내선 제거하기 | View > Rulers and Grid > Clear Guides를 선택합니다 |

안내선은 배치한 페이지에 속합니다. 문서가 열려 있는 동안 유지되며 문서에 저장되지 않습니다.

## 격자

View > Rulers and Grid > Show Grid(⌘')를 선택하면 모든 페이지에 왼쪽 상단 모서리부터 격자가 그려집니다. 간격은 View > Rulers and Grid > Grid Spacing에서 선택합니다. 다섯 번째 선마다 더 진하게 표시됩니다.

View > Rulers and Grid에서 **Snap to Guides and Grid**가 켜져 있으면 측정의 점이 포인터 근처의 안내선과, 격자가 표시되어 있는 동안에는 격자에 맞춰집니다. Vertex Magnetic Snapping으로 모서리에 맞춰지는 것과 같습니다.

## Inspector {#the-inspector}

View > Show Inspector(⌃⌘I)를 선택하면 페이지 옆에 Inspector가 표시됩니다. 페이지를 오른쪽 클릭하고 Inspect를 선택할 수도 있습니다. [Search를 오른쪽으로 옮긴](search.md#see-results-beside-the-outline) 경우 둘이 오른쪽 영역을 함께 사용합니다. 상단의 Search 및 Inspector 버튼으로 전환합니다.

- **텍스트, 이미지 및 그림:** Inspector가 열린 상태에서 Select 모드로 페이지를 클릭합니다. Inspector에 그곳에 그려진 내용이 표시되고 페이지에서는 그 부분에 테두리가 표시됩니다.
  - **텍스트:** 서체, 크기, 문자, 색상과 색 공간, 그리고 서체가 파일에 포함되어 있는지 여부. 포함되지 않은 서체는 대체 서체로 그려지므로 인쇄하면 다르게 보일 수 있습니다.
  - **이미지:** 픽셀 크기, 페이지에 배치된 상태의 해상도, 페이지에서의 크기, 색 공간, 구성 요소당 비트 수. 인쇄하거나 최적화하기 전에 이미지의 해상도를 확인하십시오.
  - **그림:** 선의 두께와 색상, 또는 도형의 채우기 색상.
- **주석:** 주석을 선택하면 종류, 작성자, 날짜, 레이어, 불투명도 및 색상을 볼 수 있습니다. 이동하려면 위치(페이지 왼쪽 상단 모서리부터의 **X**와 **Y**)를 입력하고 Return 키를 누릅니다. 사각형, 타원, 텍스트 상자, 콜아웃, 스탬프, 수정 구름은 크기도 바꿀 수 있습니다. **Width**와 **Height**를 입력합니다.

## 탐색기

View > Show Navigator(⌃⌘N)를 선택하면 윈도우 모서리에 보고 있는 페이지의 축소판이 표시됩니다. 화면에 보이는 부분에는 테두리가 표시됩니다. 테두리를 드래그하거나 축소판을 클릭하여 크게 확대한 상태로 큰 시트를 돌아다닙니다.

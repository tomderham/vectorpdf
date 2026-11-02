<!-- keywords: 페이지 레이블, 페이지 번호, 도면 번호, 탐색, 이동, 스크롤, 페이지, 페이지로 이동, 뒤로, 앞으로, 화살표 키, navigate, navigation, scroll, page, pages, go to page, page labels, page numbers, sheet numbers, back, forward, arrow keys, jump -->
<!-- source: e30f4f6cb6d9 -->

# 문서 내에서 이동하기

## 스크롤 및 페이지 넘기기

트랙패드나 마우스로 스크롤합니다. VectorPDF는 읽고 있는 위치 근처의 페이지만 레이아웃하므로 아주 긴 문서에서도 빠르게 동작합니다.

키보드 사용 시:

| 키 | 동작 |
| --- | --- |
| Left Arrow, Right Arrow | 이전 또는 다음 페이지 |
| Up Arrow, Down Arrow | 윈도우보다 긴 페이지 안에서 스크롤한 다음 다음 페이지로 이동합니다. 페이지가 윈도우에 맞으면 한 페이지씩 이동합니다. |
| Page Up, Page Down | 더 큰 단위로 스크롤한 다음 다음 페이지로 이동합니다. |
| Space, ⇧Space | 앞으로 또는 뒤로 이동합니다. Page Down 및 Page Up과 같습니다. |
| ⌥Up Arrow, ⌥Down Arrow, ⌥Left Arrow, ⌥Right Arrow | 이전 또는 다음 페이지 |
| ⌘Up Arrow, ⌘Down Arrow | 첫 페이지 또는 마지막 페이지 |

Two-Page Mode에서는 이 키를 사용하면 두 페이지 펼침면이 통째로 넘어갑니다.

## 특정 페이지로 이동하기

도구 막대의 페이지 번호를 클릭하고 원하는 페이지를 입력한 다음 Return 키를 누릅니다. 취소하려면 Escape 키를 누릅니다.

일부 문서는 앞부분의 `iv`나 도면의 `A-101`처럼 페이지에 자체 이름을 붙입니다. 이 경우 VectorPDF는 도구 막대, 페이지 표시기, 썸네일에 해당 레이블을 표시하고, `iv (4 of 300)`처럼 페이지의 위치도 함께 보여 줍니다. 레이블을 입력하면 해당 페이지로 이동합니다. 같은 레이블이 여러 번 사용되었다면 그 레이블이 있는 다음 페이지로 이동합니다. 위치로 페이지를 찾아가려면 `#13`처럼 `#`와 번호를 입력합니다.

Print와 Split PDF는 항상 파일의 첫 페이지부터 센 위치로 페이지를 계산합니다.

## 이전 위치로 돌아가기

링크를 따라가거나 결과로 이동한 후 돌아가려면 Go > Back(⌘[)을 선택합니다. Go > Forward(⌘])를 선택하면 반대 방향으로 이동합니다.

## 문서의 구조 활용하기

- [개요](outline-and-thumbnails.md)를 사용하면 어느 섹션으로든 이동할 수 있습니다.
- [축소판](outline-and-thumbnails.md)에는 모든 페이지가 표시됩니다.
- [앵커](anchors.md)는 다시 돌아오고 싶은 위치를 표시합니다.
- [Link Peek](link-peek.md)은 현재 페이지를 벗어나지 않고 링크 대상을 보여 줍니다.

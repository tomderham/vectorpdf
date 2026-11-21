<!-- keywords: 저장, 다른 이름으로 저장, 저장되지 않음, 공유, Finder에서 보기, 변경 사항, 마지막 저장 버전으로 복귀, 되돌리기, 다시 불러오기, 변경 사항 버리기, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all, 자동 저장, 복구, 충돌, 예기치 않은 종료, autosave, recover, recovery, crash, quit unexpectedly -->
<!-- source: 9cd8a419ddbd -->

# 변경 사항 저장하기

마크업, 양식 입력, 페이지 변경, 가림 처리는 저장하기 전까지 파일에 기록되지 않습니다. 저장하지 않은 변경 사항이 있는 윈도우는 닫기 버튼에 점이 표시됩니다.

| 원하는 작업 | 방법 |
| --- | --- |
| 저장하기 | File > Save를 선택하거나 ⌘S 키를 누릅니다. |
| 새로운 이름으로 사본 저장하기 | File > Save As를 선택하거나 ⇧⌘S 키를 누릅니다. |
| 암호로 보호된 사본 저장하기 | File > [Save Encrypted with Password](passwords.md)를 선택하거나 ⌥⌘S 키를 누릅니다. |

저장하지 않은 변경 사항이 있는 문서를 닫으면 VectorPDF에서 저장할지 묻습니다.

[디지털 서명](digital-signatures.md)된 문서는 서명된 부분 뒤에 변경 사항을 추가하는 방식으로 저장되므로, 변경이 허용되는 범위에서 서명이 유효하게 유지됩니다.

## 변경 사항 버리기

마지막으로 저장한 이후의 모든 변경 사항을 버리려면 File > Revert to Saved를 선택합니다. VectorPDF는 먼저 확인한 다음, 마지막으로 저장된 상태의 파일을 읽고 있던 페이지에서 엽니다. 이 작업은 실행 취소할 수 없습니다.

문서의 크기를 줄인 사본을 만들려면 [Optimized PDF](export.md#optimized-pdf)를 참고합니다.

## VectorPDF가 예기치 않게 종료된 경우 {#if-vectorpdf-quits-unexpectedly}

문서에 저장하지 않은 변경 사항이 있으면 VectorPDF는 그 문서의 사본을 Mac에 보관하고 약 30초마다 업데이트합니다. VectorPDF가 예기치 않게 종료되면 다음에 열 때 사본을 제안합니다.

- **Open Recovered Copy**는 각 사본을 원본 옆에 "(Recovered)"라는 이름으로 저장하고 엽니다. 원본은 변경되지 않습니다. 둘을 비교한 다음 원하는 것을 남깁니다.
- **Decide Later**는 사본을 보관하고 다음에 다시 묻습니다.
- **Discard Changes**는 사본을 삭제합니다.

문서를 저장하거나, 저장된 상태로 되돌리거나, 저장하지 않고 닫을 때, 그리고 VectorPDF를 종료할 때 사본이 삭제됩니다. 암호로 보호된 문서는 사본이 암호화되지 않으므로 복사하지 않습니다. 디지털 서명된 문서도 복사하지 않습니다. 서명된 문서는 저장할 때마다 파일 안에 개정판으로 남기 때문에, 저장하기 전에 했다가 되돌린 변경 사항도 파일에 남게 됩니다. 서명된 문서는 작업하면서 직접 저장하십시오.

## 문서 공유하기

macOS 공유 서비스를 사용하려면 File > Share를 선택하고, 파일을 찾으려면 File > Show in Finder(⇧⌘R)를 선택합니다. Start 화면에서 문서를 오른쪽 클릭하면 Finder에서 볼 수 있습니다.

## PDF에 저장되지 않는 항목

[앵커](anchors.md), [읽던 위치](reading-positions.md), 보기 회전, [OCR](scanned-pages.md) 텍스트는 VectorPDF에 남아 있으며 파일과 함께 이동하지 않습니다. 단, OCR 텍스트는 [PDF에 저장](scanned-pages.md#save-the-recognized-text-in-the-pdf)할 수 있습니다.

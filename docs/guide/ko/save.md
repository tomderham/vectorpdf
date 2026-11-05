<!-- keywords: 저장, 다른 이름으로 저장, 저장되지 않음, 공유, Finder에서 보기, 변경 사항, 마지막 저장 버전으로 복귀, 되돌리기, 다시 불러오기, 변경 사항 버리기, save, save as, unsaved, share, Show in Finder, changes, PDF, revert, revert to saved, reload, discard, undo all -->
<!-- source: 2c2bdeb1617c -->

# 변경 사항 저장하기

마크업, 양식 입력, 페이지 변경, 가림 처리는 저장하기 전까지 파일에 기록되지 않습니다. 저장하지 않은 변경 사항이 있는 윈도우는 닫기 버튼에 점이 표시됩니다.

| 원하는 작업 | 방법 |
| --- | --- |
| 저장하기 | File > Save를 선택하거나 ⌘S 키를 누릅니다. |
| 새로운 이름으로 사본 저장하기 | File > Save As를 선택하거나 ⇧⌘S 키를 누릅니다. |
| 암호로 보호된 사본 저장하기 | File > [Save Encrypted with Password](passwords.md)를 선택하거나 ⌥⌘S 키를 누릅니다. |

저장하지 않은 변경 사항이 있는 문서를 닫으면 VectorPDF에서 저장할지 묻습니다.

## 변경 사항 버리기

마지막으로 저장한 이후의 모든 변경 사항을 버리려면 File > Revert to Saved를 선택합니다. VectorPDF는 먼저 확인한 다음, 마지막으로 저장된 상태의 파일을 읽고 있던 페이지에서 엽니다. 이 작업은 실행 취소할 수 없습니다.

문서의 크기를 줄인 사본을 만들려면 [Optimized PDF](export.md#optimized-pdf)를 참고합니다.

## 문서 공유하기

macOS 공유 서비스를 사용하려면 File > Share를 선택하고, 파일을 찾으려면 File > Show in Finder(⇧⌘R)를 선택합니다. Start 화면에서 문서를 오른쪽 클릭하면 Finder에서 볼 수 있습니다.

## PDF에 저장되지 않는 항목

[앵커](anchors.md), [읽던 위치](reading-positions.md), 보기 회전, [OCR](scanned-pages.md) 텍스트는 VectorPDF에 남아 있으며 파일과 함께 이동하지 않습니다.

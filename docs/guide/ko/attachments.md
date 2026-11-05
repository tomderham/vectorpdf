<!-- keywords: 첨부 파일, 첨부, 내장된 파일, 클립, 포트폴리오, 전자 인보이스, 전자 송장, 첨부 파일 저장, 추출, attachments, attachment, attached files, embedded files, paperclip, portfolio, e-invoice, electronic invoice, ZUGFeRD, Factur-X, XML, Quick Look, save attachment, extract -->
<!-- source: e084e93b9409 -->

# PDF에 첨부된 파일

PDF는 다른 파일을 안에 담을 수 있습니다. 예를 들어 보고서에 딸린 스프레드시트, 도면 세트에 딸린 CAD 모델, 전자 인보이스의 데이터 등입니다. 문서에 첨부 파일이 있으면 사이드바 상단에 Attachments 탭(클립)이 나타납니다. 첨부 파일이 있는 한두 페이지짜리 문서는 Attachments 탭이 열린 상태로 열립니다.

각 첨부 파일에는 이름과, PDF에 포함된 경우 설명, 크기 및 첨부된 페이지가 표시됩니다. 첨부 파일 위에 포인터를 올려 놓으면 파일 종류와 날짜를 볼 수 있습니다.

| 작업 | 방법 |
| --- | --- |
| 첨부 파일 미리 보기 | 이중 클릭하거나, 선택한 다음 스페이스 바를 누릅니다 |
| 다음 또는 이전 첨부 파일 미리 보기 | Quick Look이 열려 있는 상태에서 아래쪽 또는 위쪽 화살표 키를 누릅니다 |
| 해당 앱에서 열기 | 오른쪽 클릭한 다음 Open을 선택합니다 |
| 사본 저장하기 | 오른쪽 클릭한 다음 Save As…를 선택하거나, Finder로 드래그합니다 |
| 모두 저장하기 | 탭 상단의 Save All…을 클릭한 다음 폴더를 선택합니다 |
| 첨부된 페이지로 이동하기 | 오른쪽 클릭한 다음 Show on Page를 선택합니다 |

> **경고:** 첨부 파일은 앱이나 스크립트를 포함하여 어떤 종류의 파일이든 될 수 있습니다. 신뢰하는 파일만 여십시오. VectorPDF는 PDF에서 꺼낸 파일을 다운로드한 파일로 표시하므로, 웹에서 받은 파일과 마찬가지로 macOS가 앱과 스크립트를 실행하기 전에 확인합니다.

## 전자 인보이스

ZUGFeRD 및 Factur-X 인보이스는 데이터를 XML 파일에 담고 있으며, 이 파일의 이름은 보통 `factur-x.xml` 또는 `zugferd-invoice.xml`입니다. 이 파일은 다른 첨부 파일과 함께 나열되므로 회계 소프트웨어용으로 저장할 수 있습니다. VectorPDF는 인보이스의 세부 사항을 직접 표시하지 않습니다.

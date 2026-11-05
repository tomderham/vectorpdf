<!-- keywords: 개인정보, 개인정보 보호, 데이터, 네트워크, 원격 측정, 분석, 보안, 최근 검색, privacy, data, network, telemetry, analytics, iCloud, security -->
<!-- source: 936fa61fbdbf -->

# 개인정보 보호

VectorPDF에는 계정, 분석, 원격 측정, 충돌 보고 기능이 없습니다. 문서는 Mac에서 처리되며, 문서의 어떤 내용도 개발자에게 전송되지 않습니다.

## 네트워크를 사용하는 기능

- **업데이트 확인:** VectorPDF는 약 하루에 한 번 또는 Check for Updates를 선택할 때 GitHub에 최신 버전을 요청합니다. 요청에는 사용자나 문서에 관한 정보가 포함되지 않습니다. [Settings](settings.md)에서 이 기능을 끌 수 있습니다.
- **Agent:** On-Device 엔진을 사용하면 아무것도 Mac 밖으로 전송되지 않습니다. [Private Cloud Compute 및 온라인 모델](agent-engines.md)은 질문할 때에만 질문과 문서의 구절을 전송합니다. 온라인 모델을 설정할 때도 키를 사용하여 모델 목록을 가져오고 짧은 테스트를 전송합니다.
- **iCloud:** 읽기 상태는 사용자의 iCloud 계정에 보관됩니다. 여기에는 파일 위치, 마지막 페이지와 확대/축소 비율, 앵커의 이름, 발췌문, 페이지가 포함됩니다. 문서, 문서의 전체 텍스트, 앵커 축소판은 업로드되지 않습니다. 최근 검색도 그곳에 보관됩니다.
- **클릭한 링크**는 브라우저에서 열립니다.
- **Apple 서비스:** 번역, 찾아보기, 음성, OCR은 macOS에서 제공되며 Apple에서 언어 파일을 다운로드할 수 있습니다. Handoff는 읽고 있는 문서와 페이지를 사용자의 다른 기기와 공유합니다.

## Mac에 저장되는 항목

VectorPDF는 환경설정, 즐겨찾기, 탭 그룹, 읽던 위치, 앵커, 스탬프를 저장합니다. 또한 Agent와 함께 사용한 문서의 색인, 앵커 축소판, 저장하지 않은 페이지 편집이나 가림 처리가 있는 문서의 임시 작업 사본을 보관하며, 임시 작업 사본은 작업이 끝나면 삭제합니다.

각 문서의 최근 검색도 저장합니다. 이 모든 것이 차지하는 공간을 확인하거나 지우려면 [Settings](settings.md#free-up-space-or-remove-data)의 Storage를 사용합니다.

온라인 모델 API 키는 로그인 키체인에 저장됩니다.

자세한 내용은 [GitHub의 개인정보 처리방침](https://github.com/tomderham/vectorpdf/blob/main/PRIVACY.md)을 참조하십시오.

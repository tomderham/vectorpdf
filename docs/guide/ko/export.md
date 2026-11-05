<!-- keywords: 내보내기, 변환, 일반 텍스트, 텍스트, 평면화, 주석 요약, 최적화, 파일 크기 줄이기, 압축, 작게, 이미지, 서체, 윤곽선, 텍스트를 윤곽선으로, 플로터, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF, optimize, optimized, reduce file size, compress, smaller, downsample, images, fonts, subset, outlines, text to outlines, plotter -->
<!-- source: 0e99b5515751 -->

# 다른 포맷으로 내보내기

문서 전체를 내보내려면 File > Export Document As를 선택한 다음 Plain Text, Word Document, Scalable Vector Graphics, Flattened PDF 또는 Optimized PDF를 선택합니다. 주석 요약과 측정에는 각각 별도의 명령이 있습니다.

## 일반 텍스트(Plain Text)

문서의 텍스트를 `.txt` 파일로 저장합니다.

## Word 문서(Word Document)

Word 및 다른 앱에서 편집할 수 있는 `.docx` 파일을 저장합니다. 복잡한 페이지 레이아웃은 PDF와 다르게 보일 수 있습니다.

## SVG

각 페이지를 Scalable Vector Graphics 파일로 저장합니다. 텍스트가 벡터 패스로 저장되므로 PDF와 똑같이 보입니다. 여러 페이지로 된 문서는 페이지당 파일 하나가 들어 있는 폴더로 저장됩니다.

## 평면화된 PDF(Flattened PDF) {#flattened-pdf}

주석과 양식 필드를 페이지의 일부로 만든 PDF를 저장하므로 이 항목들을 변경할 수 없습니다. 저장 대화상자에서 평면화할 항목을 선택합니다.

- **Flatten annotations and markups**
- **Flatten form fields (make static)**

> **참고:** 평면화해도 아래에 있는 내용은 제거되지 않습니다. 내용을 제거하려면 [가림 처리](redact.md)를 사용합니다.

## 최적화된 PDF(Optimized PDF) {#optimized-pdf}

아직 저장하지 않은 변경 사항을 포함하여 PDF의 크기를 줄인 사본을 저장합니다. 열려 있는 문서는 바뀌지 않습니다. 문서에서 더 이상 사용하지 않는 데이터는 제거되고, 중복 항목은 병합되며, 모든 항목이 압축됩니다. 저장 대화상자에서 다음 항목도 선택할 수 있습니다.

- **Keep only the characters each font uses:** 내장된 서체 중 문서에서 사용하지 않는 부분을 제거합니다. 기본적으로 켜져 있습니다.
- **Images:** 이미지를 그대로 두거나 300dpi(인쇄용) 또는 150dpi(화면에서 읽기용)로 줄입니다. 그보다 해상도가 높은 이미지만 줄어듭니다. 사진은 JPEG로 저장되고, 다이어그램과 스크린샷은 손실 없이 유지됩니다. 흑백 스캔은 변경되지 않습니다.
- **Convert text to outlines:** 모든 글자를 도형으로 그려서, 문서의 서체가 없는 플로터, 커터, 인쇄 시스템에서도 문서가 똑같이 보이게 합니다. 사본의 텍스트는 선택, 검색 또는 복사할 수 없습니다.

사본이 얼마나 작아지는지는 문서에 따라 다릅니다. 이미지를 줄이면 스캔과 사진이 가장 많이 작아집니다.

## 주석 요약

다른 앱의 주석을 포함한 문서의 주석 목록을 작성자, 상태 및 답글과 함께 저장하려면 File > Export Annotations Summary(⇧⌘E)를 선택합니다. 기본적으로 Markdown 파일로 저장됩니다. 대신 스프레드시트로 저장하려면 파일 확장자를 `.csv`로 지정합니다.

## 측정

측정을 내보내려면 [물량 산출표](takeoff.md)를 사용합니다.

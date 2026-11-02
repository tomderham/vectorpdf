<!-- keywords: 내보내기, 변환, 일반 텍스트, 텍스트, 평면화, 주석 요약, export, convert, plain text, text, Word, docx, SVG, flatten, flattened, annotations summary, CSV, Markdown, PDF -->
<!-- source: c72be921ec25 -->

# 다른 포맷으로 내보내기

문서 전체를 내보내려면 File > Export Document As를 선택한 다음 Plain Text, Word Document, Scalable Vector Graphics 또는 Flattened PDF를 선택합니다. 주석 요약과 측정에는 각각 별도의 명령이 있습니다.

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

## 주석 요약

다른 앱의 주석을 포함한 문서의 주석 목록을 작성자, 상태 및 답글과 함께 저장하려면 File > Export Annotations Summary(⇧⌘E)를 선택합니다. 기본적으로 Markdown 파일로 저장됩니다. 대신 스프레드시트로 저장하려면 파일 확장자를 `.csv`로 지정합니다.

## 측정

측정을 내보내려면 [물량 산출표](takeoff.md)를 사용합니다.

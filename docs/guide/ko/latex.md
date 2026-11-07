<!-- keywords: LaTeX, TeX, SyncTeX, 정방향 검색, 역방향 검색, 소스, 소스 코드, 편집기, 소스로 이동, LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->
<!-- source: a865c846e0d7 -->

# LaTeX 소스와 PDF 간에 이동하기

LaTeX로 작성하는 경우, VectorPDF를 사용하여 PDF의 특정 위치에서 그 위치를 만든 소스 줄로, 그리고 소스 줄에서 그 줄이 PDF에 만든 위치로 이동할 수 있습니다. 이 기능은 SyncTeX를 사용하며, SyncTeX는 TeX가 `-synctex=1`로 빌드할 때 켜집니다. 대부분의 LaTeX 편집기는 이렇게 빌드합니다.

SyncTeX는 PDF와 같은 이름의 SyncTeX 파일이 옆에 있는 PDF에서 작동합니다(`paper.pdf`와 `paper.synctex.gz`). 폴더의 다른 PDF에는 영향을 주지 않습니다.

## 편집기 선택하기

1. VectorPDF > Settings를 선택한 다음, LaTeX (SyncTeX) 옆의 Set Up…을 클릭합니다.
2. Source Editor에서 편집기를 선택합니다: Visual Studio Code, VSCodium, Cursor, Zed, Sublime Text, BBEdit, TextMate, MacVim, Emacs, TeXstudio.
3. 편집기가 목록에 없으면 Other를 선택하고 파일을 특정 줄에서 여는 명령을 입력합니다. 파일은 `%file`, 줄은 `%line`으로 씁니다(예: `myeditor +%line %file`).

편집기 아래에 Settings가 찾은 프로그램이 표시됩니다. 프로그램을 찾을 수 없다고 표시되면 편집기의 명령줄 도구를 설치하거나, Other를 선택하고 프로그램의 전체 경로를 입력하십시오.

## PDF에서 소스로 이동하기

PDF의 위치를 ⇧⌘을 누른 채 클릭합니다. 편집기가 그 위치를 만든 줄에서 소스 파일을 엽니다.

오른쪽 클릭하고 **Show in Editor**를 선택할 수도 있습니다. SyncTeX 파일이 있는 PDF의 메뉴 맨 위에 있습니다.

## 소스에서 PDF로 이동하기

편집기는 VectorPDF에 포함된 `displayline`을 실행하여 VectorPDF에 줄을 표시하도록 요청합니다:

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

VectorPDF는 PDF를 앞으로 가져오고(열려 있지 않으면 열고), 해당 줄을 잠시 빨간색으로 강조 표시합니다. 줄이 이미 화면에 있으면 스크롤하지 않습니다. LINE 앞에 `-g`를 추가하면 VectorPDF가 편집기 뒤에 머무릅니다.

`displayline`은 Skim의 것과 같은 인수를 받습니다. 편집기에 Skim용 설정이 있으면 대신 VectorPDF의 `displayline`을 사용하십시오.

### Visual Studio Code

LaTeX Workshop 확장 프로그램을 사용하는 경우, 설정에 다음 줄을 추가합니다. 설정은 명령 팔레트에서 Preferences: Open User Settings (JSON)을 선택하면 열립니다.

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

그런 다음 Visual Studio Code에서 ⌥⌘B를 눌러 빌드하고, ⌥⌘V를 눌러 VectorPDF에서 PDF를 열고, ⌥⌘J를 눌러 현재 줄을 표시합니다. 마지막 설정을 사용하면 빌드할 때마다 VectorPDF가 그 줄도 표시합니다.

## 작성하는 동안

편집기가 PDF를 다시 빌드하면 VectorPDF는 보던 위치, 확대/축소, 회전, 페이지 레이아웃을 유지한 채 다시 로드합니다. 파일을 아직 쓰는 중이면 끝날 때까지 기다립니다.

## 작동하지 않는 경우

- **메뉴에 Show in Editor가 없음:** PDF에 SyncTeX 파일이 없습니다. SyncTeX를 켜고 빌드한 다음, SyncTeX 파일을 PDF 옆이나 그 옆의 build 또는 out 폴더에 두십시오.
- **No Source Here:** 여백이나 그림처럼 해당 위치에 대한 소스 줄이 없습니다. 텍스트를 클릭하십시오.
- **VectorPDF에서 아무 일도 일어나지 않음:** 편집기가 VectorPDF의 `displayline`을 실행하는지, 그리고 소스를 마지막으로 변경한 후 SyncTeX를 켜고 PDF를 빌드했는지 확인하십시오.
- **TeX를 설치한 후에도 편집기가 TeX를 찾지 못함:** 편집기를 종료한 다음 다시 여십시오.

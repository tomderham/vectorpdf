<!-- keywords: Document 탭, 양식 필드, 필드, 서명, 서명됨, 디지털 서명, 인증, 링크, 하이퍼링크, URL, 웹 링크, 이름 있는 대상, 대상, 내용, 사이드바, document tab, form fields, fields, signatures, signed, digital signature, certified, links, hyperlinks, web links, named destinations, destinations, contents, sidebar, URLs -->
<!-- source: 83fd92f682a7 -->

# 양식 필드, 서명, 링크 및 대상

사이드바 상단의 Document 탭(상자)에는 문서의 페이지 외에 담긴 내용이 나열됩니다. 탭 상단의 메뉴에서 무엇을 볼지 선택합니다.

- **Layers:** [레이어 보기 및 가리기](layers.md)를 참고하십시오.
- **Attachments:** [PDF에 첨부된 파일](attachments.md)을 참고하십시오.
- **Signatures:** 문서의 디지털 서명과 각 서명이 유효한지 여부. [디지털 서명하기 및 확인하기](digital-signatures.md)를 참조하십시오.
- **Form Fields:** 양식의 모든 필드와 그 값(서명 필드 포함).
- **Links:** 모든 링크와 링크가 걸린 텍스트, 링크가 가리키는 곳.
- **Destinations:** 링크가 가리킬 수 있는 문서 안의 이름 있는 위치.

Signatures는 문서가 서명되어 있으면 항상 나열됩니다. Form Fields, Links, Destinations는 VectorPDF > Settings > General에서 **List form fields, links and destinations in the sidebar**를 켠 경우에만 나열됩니다. 대부분의 문서에는 링크가 있으므로, 그렇지 않으면 거의 모든 문서에서 탭이 나타나게 됩니다.

메뉴에는 문서에 있는 항목만 표시되며, 탭은 문서에 이 중 하나 이상이 있을 때만 나타납니다.

## 양식 필드와 서명

필드는 양식이 붙인 이름으로 페이지별로 나열됩니다. 각 필드에는 값이 표시되며, 양식에서 반드시 채워야 한다고 지정한 경우 **Required**가 표시됩니다. 필드 위에 포인터를 올려 두면 전체 이름과 종류를 볼 수 있습니다. 필드를 클릭하면 페이지의 해당 필드로 이동하며, 잠시 테두리가 표시됩니다. 필드를 채우는 방법은 [양식 채우기](forms.md)를 참고하십시오. 입력하는 동안 목록에 새 값이 표시됩니다.

서명 필드에는 누가 서명했는지와 서명이 유효한지, 또는 **Not signed**가 표시됩니다. 각 서명에 대해 더 알아보려면 탭 상단의 메뉴에서 Signatures를 선택합니다. [디지털 서명하기 및 확인하기](digital-signatures.md)를 참조하십시오.

## 링크

링크는 각 페이지를 읽는 즉시 페이지별로 나열되므로 긴 문서의 첫 링크가 바로 표시됩니다. 목록 위의 버튼을 사용하여 **All** 링크, **Web** 링크만 또는 **In Document** 링크를 표시하고, **Filter**에 입력하여 텍스트나 주소로 링크를 찾습니다.

| 작업 | 방법 |
| --- | --- |
| 링크를 해당 페이지에서 보기 | 링크를 클릭합니다 |
| 링크 따라가기 | 링크를 이중 클릭합니다. 웹 링크는 브라우저에서 열립니다. |
| 웹 주소 복사하기 | 링크를 오른쪽 클릭한 다음 Copy Address를 선택합니다 |

## 대상

대상은 `section.2`나 `figure.3`처럼 문서 안의 이름 있는 위치입니다. LaTeX 등의 프로그램이 링크가 가리킬 수 있도록 만듭니다. 대상을 클릭하면 그 위치로 이동합니다. 이름을 복사하려면 오른쪽 클릭한 다음 Copy Name을 선택합니다.

# CCL

- `document.hwp`: 기존 `Tests/CoreHwpTests/FileHeader/CCL.hwp`에서 이관.
- 목적: CCL 문서의 file header, hyperlink, shape object, `PrvImage` raw payload,
  `BinData` png storage를 검증한다.
- 재생성: 한컴오피스 한글에서 CCL 설정을 포함한 문서를 저장하고 file header 기대값을 갱신한다.

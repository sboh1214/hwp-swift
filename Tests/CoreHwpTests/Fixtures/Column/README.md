# Column

- `document.hwp`: 기존 `Tests/CoreHwpTests/Section/Column/Column.hwp`에서 이관.
- 목적: 다단 문서의 column controls, `DocumentProperties`, `DocInfo` id mappings,
  `PrvText`, `PrvImage` raw payload 길이를 검증한다.
- 재생성: 한컴오피스 한글에서 1단, 2단, 3단, 서로 다른 폭의 다단을 포함해 저장하고 기대값을 갱신한다.

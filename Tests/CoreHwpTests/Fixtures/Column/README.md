# Column

- `document.hwp`: 기존 `Tests/CoreHwpTests/Section/Column/Column.hwp`에서 이관.
- 목적: 다단 문서의 column controls, `DocumentProperties`, `DocInfo` id mappings,
  `PrvText`, `PrvImage` raw payload 길이를 검증한다.
- 보조 검증 대상 errata: rhwp `hwp_spec_errata.md` 항목 11 ColumnDef 비례 너비/간격.
  서로 다른 폭 다단의 raw bytes `00 00 63 28 d3 06 ca 50 00 00...`를
  `property2=0`, `widthArray=[10339, 20682]`, `gapArray=[1747, 0]`로 읽고
  구분선 bytes가 trailing으로 밀리지 않는지 확인한다.
- 재생성: 한컴오피스 한글에서 1단, 2단, 3단, 서로 다른 폭의 다단을 포함해 저장하고 기대값을 갱신한다.

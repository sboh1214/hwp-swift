# noori

- `document.hwp`: 기존 `Tests/CoreHwpTests/Noori/noori.hwp`에서 이관.
- 포함 기능: 실제 `DOC_DATA` record, `DOC_DATA` 하위 `FORBIDDEN_CHAR`,
  `LAYOUT_COMPATIBILITY`, compatible document child `TRACK_CHANGE`, BinData,
  table, image, styles, bullets/numbering.
- 보조 검증 대상 errata: rhwp `hwp_spec_errata.md` 항목 3 LIST_HEADER bit
  16~22. 표 셀 LIST_HEADER raw bytes에서 `listAttr=0x00200000`(vertical center)와
  `listAttr=0x00400000`(vertical bottom)을 확인한다. 이 fixture는 기존 이관본이므로,
  전용 Hancom 생성 fixture가 생기면 같은 기대값을 그쪽으로 옮긴다.
- 재생성: 동일한 공개 보도자료 형태의 문서를 한컴오피스 한글에서 저장하고 preview/table/shape/column 기대값을 갱신한다.

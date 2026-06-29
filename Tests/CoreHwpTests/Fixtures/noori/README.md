# noori

- `document.hwp`: 기존 `Tests/CoreHwpTests/Noori/noori.hwp`에서 이관.
- 포함 기능: 실제 `DOC_DATA` record, `DOC_DATA` 하위 `FORBIDDEN_CHAR`,
  `LAYOUT_COMPATIBILITY`, compatible document child `TRACK_CHANGE`, BinData,
  table, image, styles, bullets/numbering.
- 재생성: 동일한 공개 보도자료 형태의 문서를 한컴오피스 한글에서 저장하고 preview/table/shape/column 기대값을 갱신한다.

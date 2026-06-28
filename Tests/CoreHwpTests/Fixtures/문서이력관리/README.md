# 문서이력관리

- `document.hwp`: 기존 `Tests/CoreHwpTests/FileHeader/문서이력관리.hwp`에서 이관.
- 목적: document-history file header bit, DocInfo/document properties, `PrvText`,
  `PrvImage` raw payload 길이, `BinData` storage 없음 검증.
- 재생성: 한컴오피스 한글에서 문서 이력 관리를 켠 문서를 저장하고 file header 기대값을 갱신한다.

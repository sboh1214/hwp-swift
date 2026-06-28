# 변경내용추적

- `document.hwp`: 기존 `Tests/CoreHwpTests/FileHeader/변경내용추적.hwp`에서 이관.
- 이 fixture는 legacy file header 회귀 테스트입니다. 현재 `isTracingChange` bit는
  `false`이며, 본문 변경 이력 record를 포함한 실제 변경 내용 추적 문서는 아닙니다.
- 목적: legacy track-changes flag 상태, DocInfo/document properties, `PrvText`,
  `PrvImage` raw payload 길이, `BinData` storage 없음 검증.
- 재생성: 한컴오피스 한글에서 file header의 변경 내용 추적 bit 상태를 확인할 수 있는
  문서를 저장하고 기대값을 갱신한다. 실제 변경 이력 fixture를 확보하면 별도 fixture로
  추가하고 `features`에 `track-changes`를 사용한다.

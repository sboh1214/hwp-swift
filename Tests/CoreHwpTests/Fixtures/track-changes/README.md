# track-changes

- `document.hwp`: Hancom Office HWP for macOS 12.30.0 (build 6382)에서 저장한 변경 내용 추적 fixture.
- 생성일: 2026-06-15.
- 소스: 임시 DOCX package에 WordprocessingML `w:del`, `w:ins`, `w:trackRevisions`를 넣고 한컴오피스에서 열어 HWP로 다른 이름 저장.
- 포함 기능:
  - FileHeader `isTracingChange == true`
  - `DocumentProperties` section/starting index/caret location
  - `DocInfo` id mappings count와 주요 raw payload total byte count
  - `MEMO_SHAPE`, `TRACK_CHANGE_CONTENT`, `TRACK_CHANGE_AUTHOR` raw record 보존
  - `TRACK_CHANGE_CONTENT`의 kind와 변경 시각 `2026-06-15 04:30/04:31` typed 노출
  - `TRACK_CHANGE_AUTHOR`의 작성자 이름 `CoreHwp Fixture` typed 노출
  - 본문 변경 추적 표시: 삭제된 `old text`, 삽입된 `new text`
  - CoreHwp 현재 모델에서는 최종 본문 텍스트 `new text`가 보이고 변경 추적 표시는 `HwpParaText` extended inline payload 2개로 raw 보존된다.
  - `PreviewText`는 `old textnew text`를 포함한다.
  - `PreviewImage` stream
  - `BinData` storage 없음

## 재생성

1. 최소 DOCX package를 만들고 `word/settings.xml`에 `<w:trackRevisions/>`, `word/document.xml`에 `w:del`/`w:ins`를 넣는다.
2. `/Applications/Hancom Office HWP.app`으로 DOCX를 연다.
3. 화면에서 삭제/삽입 변경 내용 표시가 보이는지 확인한다.
4. `파일 > 다른 이름으로 저장하기...`에서 파일 형식을 `한글 문서 (*.hwp)`로 선택하고 `document.hwp`로 저장한다.
5. `swift test --filter FixtureManifestTests/testFixtureManifests`로 manifest 기대값을 확인한다.

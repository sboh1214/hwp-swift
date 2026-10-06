# note-reference-strikethrough

HWP fixture `note-reference-strikethrough`(`Tests/CoreHwpTests/Fixtures/note-reference-strikethrough/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **MS 워드 호환 문서**
(`hh:compatibleDocument@targetProgram="MS_WORD"`, 한글 슬롯 Apple SD 산돌고딕 Neo·나머지 슬롯 Menlo)에
취소선·글자 가운데 밑줄이 걸린 글자 사이에 각주·미주 참조 번호를 둔 7문단(꼬리표 ` #1`…` #7`) — Menlo
20·40pt 실선 취소선, 글자 가운데 밑줄, 위 첨자 글자 모양 안 번호, 긴 점선 취소선, 한글·라틴 슬롯 80pt
(쪽 나누기로 2쪽에서 시작 — 1쪽 끝의 80pt·160% 문단 프레임 아래 여분이 각주 겹침 가드에 걸리지 않게, #271) —
을 싣고(구역 각주 모양·각주 자동 번호 위 첨자), 두 포맷의 렌더가 번호에 걸린 선을 한글처럼 번호가 놓인
글자 모양의 자리·두께에, 번호를 앞뒤 글자와 따로 된 run으로 그리는지를 고정한다 (#256).
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6523)에서 HWP 쌍의 재생성 절차(`Fixtures/note-reference-strikethrough/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6523)
- 일자: 2026-10-06 (System Events 접근성 자동화로 저장)

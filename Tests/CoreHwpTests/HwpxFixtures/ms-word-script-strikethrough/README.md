# ms-word-script-strikethrough

HWP fixture `ms-word-script-strikethrough`(`Tests/CoreHwpTests/Fixtures/ms-word-script-strikethrough/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **MS 워드 호환 문서**
(`hh:compatibleDocument@targetProgram="MS_WORD"`, 한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo)에
보통·위 첨자·아래 첨자 취소선을 한 줄씩 나란히 둔 8문단(꼬리표 ` #1`…` #8`) — Menlo·Apple SD 20·40pt
실선 취소선, 글자 가운데 밑줄, 원형 점선 취소선, 기본 40pt·상대 크기 50%, 첨자 run만 글자 위치 30% — 을
싣고, 두 포맷의 렌더가 그 문서의 첨자 취소선을 한글처럼 첨자로 옮겨진 베이스라인 위 보통 글자 취소선
높이의 0.696배에 그리는지를 고정한다 (#248). `document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6523)에서 HWP 쌍의 재생성 절차(`Fixtures/ms-word-script-strikethrough/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6523)
- 일자: 2026-10-02 (System Events 접근성 자동화로 저장)

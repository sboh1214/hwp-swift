# script-strikethrough-large

HWP fixture `script-strikethrough-large`(`Tests/CoreHwpTests/Fixtures/script-strikethrough-large/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **한글 문서**
(`hh:compatibleDocument@targetProgram="HWP201X"`, 한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo)에
기본 크기 50–160pt의 보통·위 첨자·아래 첨자 취소선을 한 줄씩 나란히 둔 6문단(꼬리표 ` #1`…` #6`) —
Menlo 50·80·150·160pt와 Apple SD 100pt 실선 취소선, Menlo 100pt 글자 가운데 밑줄 — 을 싣고, 두 포맷의
렌더가 그 문서의 첨자 취소선을 한글처럼 첨자로 옮겨진 베이스라인 위 보통 글자 취소선 높이의 89/140배에
그리는지를 고정한다 (#258). `document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6523)에서 HWP 쌍의 재생성 절차(`Fixtures/script-strikethrough-large/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6523)
- 일자: 2026-10-07 (System Events 접근성 자동화로 저장)

# numbering-sequence

HWP fixture `numbering-sequence`(`Tests/CoreHwpTests/Fixtures/numbering-sequence/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. 문단 번호 정의 6종
(`hh:numbering id="1"`~`"6"`, `start` 0·0·5·0·7·9와 수준별 `hh:paraHead@start`),
구역 3개의 `hp:secPr@outlineShapeIDRef`(1·4·5), 개요 문단 6개·문단 번호 문단 14개
(표 셀 2개 포함)를 담아, 문단 번호·개요 번호 생성 규칙(#153 — 정의별 목록, 시작
번호 0의 이어 받기, 수준별 시작 번호 배열 우선, 건너뛴 수준의 암묵 매김, 표 셀의
문서 순서)을 HWP 쌍·한글.app 복사 텍스트와 대조한다
(`Tests/HwpKitCoreTests/HwpParagraphNumberingFixtureTests`).
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/numbering-sequence/README.md`)를
   따라 문서를 만든다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-06 (Claude Computer Use GUI 자동화로 저장)

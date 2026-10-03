# space-width

HWP fixture `space-width`(`Tests/CoreHwpTests/Fixtures/space-width/document.hwp`)와 같은 편집 세션에서
한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **한글 문서**(`hh:compatibleDocument@targetProgram="HWP201X"`,
한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo, 20pt)에 빈칸(U+0020) 폭 표본 7문단(꼬리표 ` #1`…` #7`) —
한글 50%·라틴 100%, 한글 100%·라틴 50%, 줄 시작·연속 빈칸, 한글·라틴 장평 50%, 글꼴에 어울리는 빈칸,
글자 모양 run 경계, 묶음 빈칸·고정폭 빈칸 — 을 싣고, 두 포맷의 렌더가 빈칸을 한글처럼 라틴 슬롯이 아니라
한글 슬롯 글자 크기 × 0.5 × 한글 장평으로 벌리는지를 고정한다 (#249,
`HwpKitTests/FixtureSpaceWidthTests.swift`). `document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6523)에서 HWP 쌍의 재생성 절차(`Fixtures/space-width/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6523)
- 일자: 2026-10-03 (System Events 접근성 자동화로 저장)

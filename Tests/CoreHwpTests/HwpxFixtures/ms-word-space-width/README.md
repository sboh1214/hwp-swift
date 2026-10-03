# ms-word-space-width

HWP fixture `ms-word-space-width`(`Tests/CoreHwpTests/Fixtures/ms-word-space-width/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **MS 워드 호환 문서**
(`hh:compatibleDocument@targetProgram="MS_WORD"`, 한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo, 20pt)에
빈칸(U+0020) 폭 표본 6문단(꼬리표 ` #1`…` #6`) — 라틴 사이·한글 앞뒤, 줄 시작·연속 빈칸, 구두점·`½` 이웃,
글자 모양 run 경계, 글꼴에 어울리는 빈칸, 묶음 빈칸·고정폭 빈칸 — 을 싣고, 두 포맷의 렌더가 그 문서에서
앞뒤가 모두 라틴 부류 글자인 빈칸만 한글처럼 라틴 글꼴 고유 폭으로 벌리고 나머지는 한글 문서와 같은 고정
폭으로 두는지를 고정한다 (#249, `HwpKitTests/FixtureSpaceWidthTests.swift`). `document.hwpx`의 파싱
기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6523)에서 HWP 쌍의 재생성 절차(`Fixtures/ms-word-space-width/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6523)
- 일자: 2026-10-03 (System Events 접근성 자동화로 저장)

# wide-tables

HWP fixture `wide-tables`(`Tests/CoreHwpTests/Fixtures/wide-tables/document.hwp`)와 같은 편집 세션에서
한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **한글 문서**(`hh:compatibleDocument@targetProgram="HWP201X"`,
A4 본문 425.2pt)에 본문·문단·셀·각주보다 넓은 표 20개 — 왼쪽·가운데·오른쪽·배분 정렬 문단의 글자처럼 취급
450pt 표, 문단 여백·들여쓰기·셀 간격, 폭 기준 '문단' 표, 문단·종이·단 기준과 정렬·오프셋·바깥 여백을 준
자리 차지 표, 각주 안 표 둘, 셀 안 350pt 표 — 와 꼬리표(`#0`…`#19`)를 싣고, 두 포맷의 렌더가 표를
줄이지 않고 한글의 가로 자리에 놓는지를 고정한다 (#254, `HwpKitTests/FixtureWideTableTests.swift`).
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다. 한글은 폭 기준 '문단' 표의 `hp:sz@width`를 문단
폭 HWPUNIT(32520)으로, 첫 칸 `hp:cellSz@width`를 29520으로 고쳐 쓰고 `@widthRelTo="PARA"`를 그대로 둔다 —
HWP 쌍과 같다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6523)에서 HWP 쌍의 재생성 절차(`Fixtures/wide-tables/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6523)
- 일자: 2026-10-05 (System Events 접근성 자동화로 저장)

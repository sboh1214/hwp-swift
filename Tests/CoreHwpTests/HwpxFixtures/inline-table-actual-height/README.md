# inline-table-actual-height

HWP fixture `inline-table-actual-height`(`Tests/CoreHwpTests/Fixtures/inline-table-actual-height/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. 셀 내용이 저작 높이보다 키운 '글자처럼
취급' 표(작은 표 9문단·각주 안 표·32행 표 3개)를 실어, HWPX 매퍼가 HWP 쌍과 같은 표 크기·바깥 여백·줄
캐시를 옮기는지와 두 포맷의 렌더가 표를 같은 자리에 놓는지를 고정한다 (#214). 한글은 저장할 때 표
공통 속성의 높이를 실제 높이로 고쳐 쓰므로, 저작 높이가 낡은 문서의 재조판은 테스트가 그 높이를
되돌려 재현한다 (`HwpKitTests/FixtureInlineTableActualHeightTests.swift`). `document.hwpx`의 파싱
기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/inline-table-actual-height/README.md`)를
   따라 합성 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-23 (System Events 접근성 자동화로 저장)

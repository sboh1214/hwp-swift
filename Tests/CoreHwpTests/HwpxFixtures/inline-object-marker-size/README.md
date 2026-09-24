# inline-object-marker-size

HWP fixture `inline-object-marker-size`(`Tests/CoreHwpTests/Fixtures/inline-object-marker-size/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. 글자처럼 취급 그림(`hp:pic`)·1칸
표(`hp:tbl`)·책갈피(`hp:bookmark`)를 본문(함초롬바탕 10pt)과 다른 글자 모양의 run(`charPrIDRef`,
대개 40pt)에 실어, HWPX 매퍼가 HWP 쌍과 같은 개체 크기·마커 글자 모양·줄 캐시를 옮기는지와 두
포맷의 렌더가 마커 크기를 줄 상자에서 빼고 비율 줄 간격 여분의 기준에만 넣는지를 고정한다
(#217). 한글이 다시 저장한 `hp:linesegarray`(`vertsize`·`baseline`·`spacing`)가 줄
상자의 오라클이다 (`HwpKitTests/FixtureInlineObjectMarkerSizeTests.swift`). `document.hwpx`의
파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/inline-object-marker-size/README.md`)를
   따라 합성 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-24 (System Events 접근성 자동화로 저장)

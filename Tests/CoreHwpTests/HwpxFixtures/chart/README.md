# chart

기존 HWP fixture `chart`(`Tests/CoreHwpTests/Fixtures/chart/document.hwp`)를
한글.app에서 재저장한 HWPX(OWPML) 쌍 fixture다. `document.hwpx`의 파싱
기대값은 `manifest.json`에 있고, HWP 원본과의 파싱 등가는
`HwpxHwpEquivalenceTests`가 검증한다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 원본 `document.hwp`를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-08-28 (Claude Computer Use GUI 자동화로 저장)

## 내장 차트 (#134)

`Contents/section0.xml`의 차트는 `<hp:switch>` 두 벌이다 — `hp:case`
(`required-namespace` 2016 `ooxmlchart`)의 `<hp:chart chartIDRef="Chart/chart1.xml">`과
`hp:default`의 `<hp:ole objectType="UNKNOWN" binaryItemIDRef="ole1" drawAspect="CONTENT">`.
파서는 `hp:default`를 채택하고 `HwpxOleMapper`가 `.ole(HwpShapeControl)`로 승격한다
(manifest `oleBinItemIds: [1]`). `BinData/ole1.ole`(15,876바이트)은 HWP 쌍의
`BIN0001.OLE`과 같은 4바이트 길이 프리픽스 + CFB이고, 차트 XML 스트림
`OOXMLChartContents`(4,926바이트)는 `Chart/chart1.xml`과도 HWP 쌍과도 바이트 동일하다
(`Contents` 스트림 1바이트만 다름). 렌더 가드는
`HwpxFixtureRenderTests.testHwpxChartBlocksMatchHwpPairs`(`.chart` 블록 1개)다.

# outline-numbering

HWP fixture `outline-numbering`(`Tests/CoreHwpTests/Fixtures/outline-numbering/document.hwp`)과
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. 개요 번호 정의
2종(`hh:numbering id="1"`·`"2"`)과 구역의 개요 번호 참조 `hp:secPr@outlineShapeIDRef="2"`,
개요 문단 3개(`hh:heading type="OUTLINE"` 수준 0-2)·문단 번호 문단 2개
(`type="NUMBER" idRef="1"`)를 담아, `HwpxSecPrMapper`의 참조 리맵(id "2" → 오프셋 1
→ `numberParaShapeId` 2)과 `HwpxNumberingMapper`의 표 39 문단 머리 정보 비기본값
매핑을 HWP 쌍과 대조한다 (#152). `id="2"` 1수준의 `align="RIGHT" useInstWidth="0"
autoIndent="0" widthAdjust="200" textOffsetType="HWPUNIT" textOffset="1000"
numFormat="ROMAN_CAPITAL"`이 HWP 쌍의 속성 `0x52`·거리 1000·너비 보정 200과 같고,
2수준 `align="CENTER"`가 `0x10D`와 같다 — 표 40 정렬·거리 종류 값 배치의 실물
근거다. 9수준 `^n)`·10수준 `^9.^10)`은 번호 형식 지시자의 경계 견본이다.
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/outline-numbering/README.md`)를
   따라 문단과 개요 번호 모양을 만든다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-05 (Claude Computer Use GUI 자동화로 저장)

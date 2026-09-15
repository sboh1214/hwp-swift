# script-decorations

HWP fixture `script-decorations`(`Tests/CoreHwpTests/Fixtures/script-decorations/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. 위/아래 첨자
(`<hh:supscript/>`·`<hh:subscript/>`) × 취소선(`hh:strikeout`)·밑줄 `CENTER`·`BOTTOM`·
`TOP`(`hh:underline@type`) 8조합과 글자 위치(`hh:offset` 50) 대조 3문단을 실어, 첨자
run의 장식선을 HWPX 매퍼가 HWP 쌍과 같은 글자 모양으로 옮기는지와 두 포맷의 렌더가
같은 자리에 선을 그리는지를 고정한다 (#179). 한글은 취소선만 켠 첨자 글자 모양을
HWPX에는 `type="NONE"` 밑줄 + `<hh:strikeout shape="SOLID">`로, HWP 쌍에는 밑줄 종류
2(가운데) + 취소선으로 이중 기록한다 (`line-shapes`와 같다 — 등가 투영이 그 이중
기록만 접는다). `document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/script-decorations/README.md`)를
   따라 합성 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-15 (System Events 접근성 자동화로 저장)

# hwp2007-decorations

HWP fixture `hwp2007-decorations`(`Tests/CoreHwpTests/Fixtures/hwp2007-decorations/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **한글 2007 호환 문서**
(`hh:compatibleDocument@targetProgram="HWP200X"`)로, 한글 슬롯 Apple SD 산돌고딕 Neo·
라틴 슬롯 Menlo의 글자 아래 밑줄(10·20·40·60pt)·글자 위 밑줄(40·60pt)·취소선(10·40pt)·
글자 가운데 밑줄(40pt)을 문단마다 하나씩 싣고, 그 뒤에 실선이 아닌 선 모양 10문단(긴 점선
10·40pt, 점선 위 밑줄, 원형 점선, 2중선, 3중선, 가는+굵은 취소선, 물결, 2중 물결 취소선,
일점쇄선 가운데 밑줄 — 자홍 `#FF00FF`)을 더해, HWPX 매퍼가 대상 프로그램을 HWP 쌍과 같은
값(`HwpCompatibleDocumentTarget.hwp200X`)으로 옮기는지와 두 포맷의 렌더가 같은 고정 두께
기하(#210)·고정 선 모양 무늬(#227)로 장식선을 그리는지를 고정한다. 2쪽이다. `document.hwpx`의
파싱 기대값은 `manifest.json`에 있다.

취소선 문단(`S10`·`S40`)은 HWP 저장본이 '글자 가운데' 밑줄 + 취소선 비트의 레거시 이중
기록인데 이 HWPX 저장본은 밑줄 없음 + `hh:strikeout`으로 접어 적는다 — 등가 투영이 그
조합을 접어 비교하는 자리다 (#136).

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/hwp2007-decorations/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-22 (#210), 재저장 2026-09-26 (#227) (System Events 접근성 자동화로 저장)

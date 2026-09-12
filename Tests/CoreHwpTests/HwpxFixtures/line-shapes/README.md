# line-shapes

HWP fixture `line-shapes`(`Tests/CoreHwpTests/Fixtures/line-shapes/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. OWPML `LINETYPE2`
이름 17종을 밑줄(`hh:underline@shape`)·취소선(`hh:strikeout@shape`)·표 셀 테두리
(`hh:borderFill`의 네 방향 `@type`)·단 구분선(`hp:colLine@type` = `DASH_DOT`)·각주/미주
구분선(`hp:noteLine@type` = `DOT`/`DASH`)에 실어, HWPX 매퍼가 이름을 HWP 쌍과 같은
값으로 옮기는지 고정한다 (#177) — 글자선은 `LINETYPE2 - 1`(실선 0), 테두리·구분선은
`LINETYPE2` 그대로(실선 1)다. 한글은 글자선 `REV3D`를 `SOLID` 글자 모양으로 접어 저장했고,
취소선만 있는 글자 모양은 `type="NONE"` 밑줄 + `<hh:strikeout shape="…">`로 적는다
(HWP 쌍은 밑줄 종류 2 + 밑줄 모양 복사 — 등가 투영이 그 이중 기록만 접는다).
`document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/line-shapes/README.md`)를
   따라 합성 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-12 (System Events 접근성 자동화로 저장)

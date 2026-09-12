# line-shapes

`document.hwp`는 한컴오피스 한글 12.30.0 (build 6446)이 2026-09-12에 저장한
binary HWP fixture다. OWPML `LINETYPE2` 이름 17종(`SOLID`·`DOT`·`DASH`·`DASH_DOT`·
`DASH_DOT_DOT`·`LONG_DASH`·`CIRCLE`·`DOUBLE_SLIM`·`SLIM_THICK`·`THICK_SLIM`·
`SLIM_THICK_SLIM`·`WAVE`·`DOUBLEWAVE`·`THICK3D`·`THICKREV3D`·`3D`·`REV3D`)을
글자선과 테두리·구분선 네 자리에 모두 실어, 한글이 HWPX 이름을 HWP5 바이너리의 어느
값으로 저장하는지 실측한 문서다 (#177). 같은 편집 세션에서 저장한 HWPX 쌍이
`HwpxFixtures/line-shapes/document.hwpx`다.

## 포함 기능

- 한 구역, 2단(`sameGap` 1134) + 단 구분선 `DASH_DOT` → `HwpColumn.dividerType` **4**
- 최상위 문단 36개: 표제 1 · "underline &lt;이름&gt;" 17 · "strikeout &lt;이름&gt;" 17 ·
  표를 품은 문단 1
- 글자 모양 39개 — `charShape[7...22]` 글자 아래 밑줄(빨강)의 밑줄 모양 **0…15**,
  `charShape[23...38]` 취소선(파랑)의 취소선 모양 **0…15**. 글자선 값은 `LINETYPE2 - 1`
  (실선 0)이고, `REV3D`(16)는 4비트 필드를 넘쳐 한글이 `SOLID` 글자 모양으로 접었다
  (밑줄·취소선 `REV3D` 문단이 각각 `charShape[7]`·`[23]`을 가리킨다). 취소선 글자
  모양은 한글의 레거시 이중 기록 그대로다 — 밑줄 종류 2(글자 가운데) + 밑줄 모양 자리에
  취소선 모양 복사 + 밑줄 색 = 취소선 색
- 테두리/배경 19개 — `borderFillId` 3…19(1-based 참조, 배열 오프셋 2…18)는 네 방향이
  같은 종류 **1…17**(`LINETYPE2` 그대로, 실선 1), 굵기 0.12 mm(index 1), 대각선
  `SOLID`(1)·0.1 mm(0)
- 17행 × 1열 표 — 행 `r`(0부터)의 셀이 `borderFillId` 3 + r을 참조하고 텍스트 "border &lt;이름&gt;"
- 각주 구분선 `DOT` → `dividerInfo.type` **2**, 미주 구분선 `DASH` → **3**
- PreviewText·PreviewImage stream, BinData storage 없음

한글은 `DOT`(글자선 1 · 테두리 2)를 **긴 점선(파선)**으로, `DASH`(글자선 2 · 테두리 3)를
**점선**으로 그린다 — 같은 세션의 PDF 내보내기 실측. 스펙 표 25의 값(1 긴 점선 · 2 점선)과
같고 OWPML 이름만 뒤바뀐 것이다.

## 재생성 절차

1. `Tests/CoreHwpTests/HwpxFixtures/plain-text-minimal/document.hwpx`를 바탕으로
   `Contents/header.xml`에 위 글자 모양 34개(`hh:underline type="BOTTOM" shape="…"`
   17개·`hh:strikeout shape="…"` 17개)와 테두리/배경 17개(네 방향 `type="…"`,
   `width="0.12 mm"`)를 더하고, `Contents/section0.xml`에 각 글자 모양을 쓰는 문단 34개와
   17행 표(`hp:tc borderFillIDRef`), `hp:colPr colCount="2"` + `hp:colLine type="DASH_DOT"`,
   `hp:footNotePr`/`hp:endNotePr`의 `hp:noteLine type="DOT"`/`"DASH"`를 적는다
   (`hp:linesegarray`는 지운다 — 한글이 다시 조판한다).
2. 그 HWPX를 한컴오피스 한글에서 연다 (`open -b com.hancom.office.hwp12.mac.general`).
3. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장.
4. **같은 편집 세션에서** 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서
   (*.hwpx)** → 저장해 `HwpxFixtures/line-shapes/document.hwpx`를 갱신한다.
5. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`의 payload
   prefix/suffix 기대값과 `charShapePropertyRawValues`·`columns`·`sections`를 갱신한 뒤
   `swift test --filter "FixtureManifestTests|HwpxHwpEquivalenceLineShapeTests|HwpxLineTypeMapperTests"`를
   실행한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-12 (System Events 접근성 자동화로 저장)

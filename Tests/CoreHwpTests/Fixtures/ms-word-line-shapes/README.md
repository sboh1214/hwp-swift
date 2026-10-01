# ms-word-line-shapes

`document.hwp`는 **MS 워드 호환 문서**(호환 문서 대상 프로그램 2, `CT_MSWORD`)에 선 모양 밑줄·
취소선 11문단을 실은 합성 HWPX를 한컴오피스 한글 12.30.0 (build 6446)에서 열어 2026-09-30에
`한글 문서 (*.hwp)`로 저장한 binary HWP fixture다. 한글이 이 문서에서 **밑줄 무늬를 글자 크기가
아니라 줄 글자 상자의 높이로** 재고 여러 줄 띠·물결을 **단선 중심에 가운데** 맞추며, 취소선 무늬는
**글자 모양 기본 크기**로 재는 규칙(#244)의 실물 근거다. 같은 편집 세션에서 저장한 HWPX 쌍
(`HwpxFixtures/ms-word-line-shapes`)과 PDF 내보내기(1쪽)가 같은 문서이고, PDF 좌표가 렌더 핀의
오라클이다 (`HwpKitTests/FixtureDecorationLineRenderTests+MsWordShapes.swift`).

글꼴은 `compat-decorations`와 같이 한글 슬롯 **Apple SD 산돌고딕 Neo**, 라틴 슬롯 **Menlo**다 —
둘 다 macOS·iOS에 기본 탑재이고 결정론 resolver(`HwpFontResolver.testDeterministic`: Menlo + 한글
대체 Apple SD Gothic Neo)가 같은 글꼴을 고르므로, 한글 PDF의 쪽 좌표를 어느 기기에서든 그대로
핀할 수 있다.

## 포함 기능

- 한 구역, 12문단(1쪽) — 첫 문단은 구역 정의만 있는 빈 문단이고, 이어 11문단이 표본마다 선 모양
  run + 꼬리표(` #0`…` #10`, Menlo 5pt) + 문단 끝 글자(꼬리표 글자 모양, 4번만 40pt)로 온다. 선 색은
  모두 자홍 `#FF00FF`, 문단 모양은 왼쪽 정렬·줄 간격 비율 130%다.
  1. `x` × 24 Menlo 20pt — 원형 점선(`CIRCLE`) 글자 아래 밑줄
  2. `가` × 9 Apple SD 40pt — 원형 점선 밑줄
  3. `A` Menlo 40pt(장식 없음) + `x` × 40 10pt 원형 점선 밑줄 — 큰 무장식 글자가 줄 상자를 정한다
  4. `x` × 60 Menlo 10pt 원형 점선 밑줄 + 40pt 문단 끝 글자 — 끝 글자가 쌓아 키운 줄 상자
  5. `x` × 24 Menlo 20pt — 긴 점선(`DOT`) 밑줄
  6. `x` × 24 Menlo 20pt — 2중선(`DOUBLE_SLIM`) 밑줄
  7. `x` × 24 Menlo 20pt — 물결(`WAVE`) 밑줄
  8. `x` × 24 Menlo 20pt — 가는+굵은 선(`SLIM_THICK`) 글자 위 밑줄
  9. `x` × 40 Menlo 기본 20pt·모든 슬롯 상대 크기 50% — 원형 점선 취소선
  10. `가나다라 abcdefg 마바사아 hijk` 기본 20pt·한글 슬롯 상대 크기 50% — 긴 점선 밑줄
  11. 같은 글자 모양 — 긴 점선 취소선
- `HWPTAG_COMPATIBLE_DOCUMENT` 대상 프로그램 2
- PreviewText/PreviewImage stream, BinData storage 없음

## 한글.app 실측 (같은 세션 PDF 내보내기, 쪽 위에서부터 pt, run 시작 x 85.08)

| 문단 | 표본 | 선 중심 y | 무늬 |
|---|---|---:|---|
| 1 | Menlo 20pt 원형 점선 밑줄 | 136.44 | 간격 4.20(35u)·칠 지름 1.80 — 줄 캐시 `vertsize` 3029 몫 |
| 2 | Apple SD 40pt 원형 점선 밑줄 | 204.72 | 9.00(75u)·3.72 — `vertsize` 6238 몫 |
| 3 | Menlo 40pt 무장식 + 10pt 원형 점선 밑줄 | 284.16 | 8.76(73u)·3.72, 첫 원 109.20 — 40pt 상자 몫 |
| 4 | Menlo 10pt 원형 점선 밑줄 + 40pt 끝 글자 | 371.52 | 2.16(18u)·1.08 — 끝 글자는 무늬 크기에 들지 않는다 |
| 5 | Menlo 20pt 긴 점선 밑줄 | 418.44 | 선 8.64(72u)·주기 13.92, 두께 1.20 |
| 6 | Menlo 20pt 2중선 밑줄 | 456.48 · 459.00 | 두께 0.84 둘 — 실선 밑줄 중심 457.74에 가운데 |
| 7 | Menlo 20pt 물결 밑줄 | 꼭짓점 494.16 ~ 497.52 | 획 0.84, 반주기 3.60 |
| 8 | Menlo 20pt 가는+굵은 위 밑줄 | 510.00 · 513.72 | 두께 1.44 · 3.12 |
| 9 | 기본 20pt·50% 원형 점선 취소선 | 565.68 | 3.00(25u)·1.32 — 기본 크기 20pt 몫 |
| 10 | 한글 슬롯 50% 긴 점선 밑줄 | 616.08 | 선 8.88(74u)·주기 14.16 — 슬롯 경계에서 한 위상 |
| 11 | 같은 글자 모양 긴 점선 취소선 | 645.72 | 선 5.64(47u)·주기 9.00 |

(u = 0.12pt, 600dpi 한 단위.) 원형 점선의 간격·경로 지름은 #239의 장치 단위 규칙에 글자 크기 대신
**줄 글자 상자의 높이**(글자 run 상자들의 합 — 문단 끝 글자·개체가 쌓이지 않은 줄에서는 한글 줄 캐시
`vertsize`와 같다; 4번 줄의 `vertsize`는 40pt 끝 글자가 쌓여 커지지만 무늬는 Menlo 10pt 상자 몫이다)를
넣은 값과 같다. 한글 문서였다면 1번의 원은 글자 크기 20pt 몫 간격 3.00·지름 1.32다.

### 남은 격차

- 대시 한 토막은 한글이 단위를 장치 단위로 반올림하므로(점선 1·1.5는 원형 점선의 점 단위 q와 같고, 긴
  점선 5번의 72/44u는 q = 14u와 다른 단위다) 우리 비례 대시(0.057 × 상자)와 주기마다 0.1pt쯤 갈린다
  (#245 계열의 기존 격차). 테스트는 누적 쪽 좌표가 아니라 이웃 조각의 주기로 잰다.
- 10·11번은 x 자리가 한글과 갈린다 — 한글은 이 글자 모양(한글 슬롯 상대 크기 50%)의 빈칸을 5.04pt로
  조판하고 우리는 라틴 슬롯 Menlo 20pt의 12.04pt로 조판해, 슬롯 경계(한글 213.96·253.44 / 우리
  228.01·262.61)와 run 끝(301.7 / 321.5)이 약 20pt 갈린다. 선 모양과 무관한 조판 격차라 테스트는 이
  표본의 x 자리를 핀하지 않고 주기가 run 끝까지 한결같은지(슬롯 경계에서 무늬가 다시 시작하지 않는지)만
  잰다.

## 재생성 절차

1. `HwpxFixtures/compat-decorations/document.hwpx`를 풀어 `header.xml`의 `hh:charPr id="0"`(모든 슬롯
   글꼴 id 1 = 한글 Apple SD 산돌고딕 Neo·라틴 Menlo)을 복제해 위 표본의 글자 모양을 만든다 —
   `height`, `hh:underline@type`(`BOTTOM`·`TOP`)·`@shape`·`@color`, `hh:strikeout@shape`·`@color`,
   `hh:relSz`(9번 모든 슬롯 50, 10·11번 `hangul="50"`). `hh:paraPr id="0"`을 복제해 왼쪽 정렬 줄 간격
   비율 130% 문단 모양을 만들고, `section0.xml`은 첫 문단(`hp:secPr`)만 남기고 위 순서의 11문단을
   `hp:linesegarray` **없이** 적는다 (한글이 새로 조판하게). 생성기는 로컬 `probes/244/gen244fx.py`다.
   `mimetype`을 `ZIP_STORED` 첫 항목으로 다시 압축한다.
2. 그 HWPX를 `open -b com.hancom.office.hwp12.mac.general`로 연다.
3. `파일 > PDF로 저장하기...`로 같은 세션의 PDF를 내보낸다 (1쪽, A4).
4. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 파일명만 입력 → 저장
   (System Events: 저장 패널 `splitter group 1`의 `pop up button 2`·`text field "별도 저장:"`·
   `button "저장"`; 같은 이름이 있으면 시트의 `button "대치"`).
5. 같은 세션에서 다시 `다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장해
   `HwpxFixtures/ms-word-line-shapes/document.hwpx`를 갱신한다.
6. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`의 기대값을 갱신한 뒤
   `swift test --filter "FixtureManifest|HwpxFixtureManifest|HwpxHwpEquivalence|FixtureRender|FixtureDecorationLineRender"`로
   검증한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-30

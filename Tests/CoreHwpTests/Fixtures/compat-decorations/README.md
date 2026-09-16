# compat-decorations

`document.hwp`는 **MS 워드 호환 문서**(호환 문서 대상 프로그램 2, `CT_MSWORD`)에 글자
장식선을 실은 합성 HWPX를 한컴오피스 한글 12.30.0 (build 6446)에서 열어 2026-09-15에
`한글 문서 (*.hwp)`로 저장한 binary HWP fixture다. MS 워드 호환 문서에서 한글이 밑줄·
취소선을 글꼴 지표로 놓는 규칙(#187)의 실물 근거이며, 같은 편집 세션에서 저장한 HWPX
쌍(`HwpxFixtures/compat-decorations`)과 PDF 내보내기 좌표가 렌더 핀의 오라클이다
(`HwpKitTests/FixtureDecorationLineRenderTests+Compat.swift`).

글꼴은 한글 슬롯 **Apple SD 산돌고딕 Neo**, 라틴 슬롯 **Menlo**다 — 둘 다 macOS·iOS에
기본 탑재이고 결정론 resolver(`HwpFontResolver.testDeterministic`: Menlo + 한글 대체
Apple SD Gothic Neo)가 같은 글꼴을 고르므로, 한글 PDF의 좌표를 어느 기기에서든 그대로
핀할 수 있다. 두 글꼴 모두 OS/2 `ulUnicodeRange2`의 CJK 비트가 켜져 있어 한글의 CJK
갈래(줄 상자 1.3 × win 상자)다.

## 포함 기능

- 한 구역, 12문단 — 첫 문단은 구역 정의만 있는 빈 문단이고 나머지 11문단은:
  1. `가나다밑줄` 10pt — 글자 아래 밑줄(초록 `#00FF00`) + 취소선(청록 `#00FFFF`)
  2. `Agpy under` 10pt — 같은 장식, 라틴 run
  3. `가나다밑줄` 20pt
  4. `Agpy under` 20pt
  5. `가나다윗줄` 10pt — 글자 위 밑줄(자홍 `#FF00FF`)
  6. `Agpy over` 10pt — 글자 위 밑줄
  7. `가나다가운데` 10pt — 글자 가운데 밑줄(파랑 `#0000FF`)
  8. `가나`(10pt, 밑줄 + 취소선) + `Agpy`(20pt, 장식 없음) — 밑줄 없는 큰 run이 줄 상자를 정한다
  9. `Agpy `(10pt, 장식 없음) + `밑줄`(10pt, 밑줄 + 취소선)
  10. `가`(10pt, 밑줄) + `나`(20pt, 밑줄) — 두 밑줄이 20pt 상자의 한 줄
  11. `끝` 10pt
- 글자 모양 14개(한글이 같은 모양을 접어 저장), `HWPTAG_COMPATIBLE_DOCUMENT` 대상 프로그램 2
- PreviewText/PreviewImage stream, BinData storage 없음

## 한글.app 실측 (같은 세션 PDF 내보내기, 베이스라인 기준 em, 위가 양수)

| 문단 | 글꼴·크기 | 밑줄 중심 | 밑줄 두께 | 취소선·가운데 중심 | 위 밑줄 중심 |
|---|---|---:|---:|---:|---:|
| 1 | Apple SD 10pt | −0.3012 | 0.0602 | +0.2530 | |
| 2 | Menlo 10pt | −0.2651 | 0.0602 | +0.2530 | |
| 3 | Apple SD 20pt | −0.2994 | 0.0599 | +0.2455 | |
| 4 | Menlo 20pt | −0.2575 | 0.0599 | +0.2575 | |
| 5 | Apple SD 10pt | | | | +0.9639 |
| 6 | Menlo 10pt | | | | +0.9518 |
| 7 | Apple SD 10pt | | | +0.2530 | |
| 8 | Apple SD 10pt run + Menlo 20pt run | −0.2575 (20pt 기준) | 0.0599 (20pt 기준) | +0.2515 (10pt 기준) | |
| 9 | Menlo 10pt run + Apple SD 10pt run | −0.3012 | 0.0602 | +0.2410 | |
| 10 | Apple SD 10pt + 20pt 밑줄 run | −0.2994 (20pt 기준, 한 줄) | 0.0599 | | |

Apple SD 산돌고딕 Neo의 win 상자(0.90/0.30)만으로는 밑줄이 −0.3252em이어야 하는데 −0.3012em
인 이유는 **문단 끝 글자**다 — 한글은 CR을 마지막 글자 모양의 라틴 슬롯 글꼴(Menlo)로
줄에 세워 줄 상자의 베이스라인이 Menlo의 1.1028em(줄 캐시 `baseline` 1104)이 되고, 밑줄은
그렇게 합친 줄 상자(높이는 Apple SD의 1.5596em = `vertsize` 1559)에서 나온다. 취소선은
run 단위라 Apple SD 자리(0.273 × 0.90)다. 라틴 run은 Menlo가 두 축 다 커 Menlo 값 그대로다.

## 재생성 절차

1. `HwpxFixtures/CharShape/document.hwpx`를 풀어 `header.xml`의 `hh:compatibleDocument`를
   `targetProgram="MS_WORD"`로, `hh:fontfaces`를 HANGUL = Apple SD 산돌고딕 Neo · LATIN = Menlo
   (나머지 언어는 Apple SD)로 바꾸고, `hh:charPr id="0"`을 복제해 위 조합의 글자 모양을 만든
   뒤 `section0.xml`은 첫 문단(`hp:secPr`)만 남기고 위 순서의 11문단을 `hp:linesegarray`
   **없이** 적는다 (한글이 새로 조판하게). `mimetype`을 `ZIP_STORED` 첫 항목으로 다시 압축한다.
2. 그 HWPX를 `open -b com.hancom.office.hwp12.mac.general`로 연다.
3. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 파일명만
   입력 → 저장 (System Events: 저장 패널 `splitter group 1`의 `pop up button 2`·
   `text field "별도 저장:"`·`button "저장"`; 같은 이름이 있으면 시트의 `button "대치"`).
4. 같은 세션에서 다시 `다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** →
   저장해 `HwpxFixtures/compat-decorations/document.hwpx`를 갱신한다.
5. `파일 > PDF로 저장하기...`로 오라클 PDF를 내보내 벡터 좌표(PyMuPDF `rawdict`의
   글자 `origin`, `get_drawings()`의 색 선)를 읽는다.
6. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`을 갱신한 뒤
   `swift test --filter "FixtureManifestTests|HwpxHwpEquivalenceTests|FixtureDecorationLineRenderTests"`를
   실행한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-15

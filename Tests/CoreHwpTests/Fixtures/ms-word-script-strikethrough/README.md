# ms-word-script-strikethrough

`document.hwp`는 **MS 워드 호환 문서**(호환 문서 대상 프로그램 2, `CT_MSWORD`)에 보통·위 첨자·아래 첨자
취소선을 한 줄씩 나란히 둔 8문단을 실은 합성 HWPX를 한컴오피스 한글 12.30.0 (build 6523)에서 열어
2026-10-02에 `한글 문서 (*.hwp)`로 저장한 binary HWP fixture다. 한글이 이 문서에서 **위·아래 첨자 run의
취소선을 첨자로 옮겨진 베이스라인 위, 같은 글꼴·기본 크기 보통 글자 취소선 높이의 0.696배에** 그리는
규칙(#248 — 한글 문서·한글 2007 호환 문서는 89/140배, #258·#179)의 실물 근거다. 같은
편집 세션에서 저장한 HWPX 쌍(`HwpxFixtures/ms-word-script-strikethrough`)과 PDF 내보내기(1쪽)가 같은
문서이고, PDF 좌표가 렌더 핀의 오라클이다 (`HwpKitTests/FixtureDecorationLineRenderTests+MsWordScript.swift`).

글꼴은 `compat-decorations`·`ms-word-line-shapes`와 같이 한글 슬롯 **Apple SD 산돌고딕 Neo**, 라틴
슬롯 **Menlo**다 — 둘 다 macOS·iOS에 기본 탑재이고 결정론 resolver(`HwpFontResolver.testDeterministic`:
Menlo + 한글 대체 Apple SD Gothic Neo)가 같은 글꼴을 고르므로, 한글 PDF의 쪽 좌표를 어느 기기에서든
그대로 핀할 수 있다.

## 포함 기능

- 한 구역, 9문단(1쪽) — 첫 문단은 구역 정의만 있는 빈 문단이고, 이어 8문단이 표본마다 **보통 run +
  빈칸 2개 + 위 첨자 run + 빈칸 2개 + 아래 첨자 run** + 꼬리표(` #1`…` #8`, Menlo 5pt) + 문단 끝
  글자(꼬리표 글자 모양)로 온다. 선 색은 보통 청록 `#00FFFF`, 위 첨자 자홍 `#FF00FF`, 아래 첨자 초록
  `#00FF00`이고 빈칸은 장식이 없다(크기는 표본과 같다, 7번만 20pt). 문단 모양은 왼쪽 정렬·줄 간격 비율
  160%다.
  1. `xxxx` Menlo 20pt — 실선 취소선
  2. `가나` Apple SD 20pt — 실선 취소선
  3. `xxx` Menlo 40pt — 실선 취소선
  4. `가` Apple SD 40pt — 실선 취소선
  5. `xxxx` Menlo 20pt — 실선 **글자 가운데 밑줄**(밑줄 종류 `CENTER`)
  6. `xxxxxx` Menlo 20pt — **원형 점선**(`CIRCLE`) 취소선
  7. `xxxx` Menlo **기본 40pt·모든 슬롯 상대 크기 50%** — 실선 취소선 (글리프 20pt, 첨자 12.8pt)
  8. `xxxx` Menlo 20pt — 실선 취소선, **첨자 run만 글자 위치 30%**(6pt 아래)
- `HWPTAG_COMPATIBLE_DOCUMENT` 대상 프로그램 2
- PreviewText/PreviewImage stream, BinData storage 없음

## 한글.app 실측 (같은 세션 PDF 내보내기, 쪽 위에서부터 pt)

| 문단 | 표본 | 베이스라인 | 보통 | 위 첨자 | 아래 첨자 |
|---|---|---:|---:|---:|---:|
| 1 | Menlo 20pt | 133.44 | 128.28 | 121.08 | 132.24 |
| 2 | Apple SD 20pt | 181.92 | 176.88 | 169.56 | 180.84 |
| 3 | Menlo 40pt | 253.80 | 243.60 | 229.20 | 251.52 |
| 4 | Apple SD 40pt | 350.76 | 340.80 | 326.16 | 348.60 |
| 5 | Menlo 20pt 가운데 밑줄 | 428.40 | 423.36 | 416.04 | 427.32 |
| 6 | Menlo 20pt 원형 점선 | 476.88 | 471.84 | 464.52 | 475.68 |
| 7 | Menlo 기본 40pt·50% | 547.44 | 537.24 | 522.72 | 545.16 |
| 8 | Menlo 20pt + 글자 위치 30% | 622.20 | 617.16 | 609.84 | 621.12 |

(선 중심 y. 첨자 글리프는 0.64배이고 위 첨자는 기본 크기의 0.44배 위, 아래 첨자는 0.12배 아래다 — 1번
위 첨자 글리프 베이스라인 124.56·아래 첨자 135.84, 8번은 글자 위치 몫까지 619.44·630.60.) 보통 글자
취소선은 베이스라인 위 0.23 × 글꼴 줄 상자의 베이스라인 높이 × 기본 크기(#257 — Menlo 20pt 5.07pt, 40pt
10.15pt; Apple SD 20pt 4.97pt, 한글 5.04pt)이고, 첨자 취소선은 **첨자로 옮겨진 베이스라인** 위 그 높이의 약 0.696배다
(Menlo 20pt: 위 첨자 124.56 − 3.48 = 121.08). 0.64배(첨자 글리프 축소 비율)였다면 위 첨자 선이
121.31(1번)·229.65(3번)으로 0.23·0.45pt 낮다. 가운데 밑줄(5번)과 원형 점선(6번)도 같은 자리이고, 상대
크기(7번)는 첨자 선 자리를 바꾸지 않으며(기본 40pt 몫 — 3번과 같은 베이스라인 간격), 글자 위치(8번)로
옮겨진 몫은 선이 따라가지 않는다(1번과 같은 간격). 선 두께는 한글·우리 모두 글자 모양 기본 크기의
장치 단위 획 0.84(20pt, 7u)·1.56pt(40pt, 13u)다 (#252 — 종전 0.04em은 0.80·1.60pt).

## 재생성 절차

1. `HwpxFixtures/compat-decorations/document.hwpx`를 풀어 `header.xml`의 `hh:charPr id="0"`(모든 슬롯
   글꼴 id 1 = 한글 Apple SD 산돌고딕 Neo·라틴 Menlo)을 복제해 위 표본의 글자 모양을 만든다 —
   `height`, `hh:strikeout@shape`·`@color` 또는 `hh:underline@type="CENTER"`·`@shape`·`@color`,
   `hh:relSz`(7번 모든 슬롯 50), `hh:offset`(8번 첨자 run 모든 슬롯 30), 위·아래 첨자는 `</hh:charPr>`
   바로 앞에 `<hh:supscript/>`·`<hh:subscript/>`. `hh:paraPr id="0"`을 복제해 왼쪽 정렬 줄 간격 비율
   160% 문단 모양을 만들고, `section0.xml`은 첫 문단(`hp:secPr`)만 남기고 위 순서의 8문단을
   `hp:linesegarray` **없이** 적는다 (한글이 새로 조판하게). 생성기는 로컬 `probes/248/gen248fx.py`다.
   `mimetype`을 `ZIP_STORED` 첫 항목으로 다시 압축한다.
2. 그 HWPX를 `open -b com.hancom.office.hwp12.mac.general`로 연다.
3. `파일 > PDF로 저장하기...`로 같은 세션의 PDF를 내보낸다 (1쪽, A4).
4. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 파일명만 입력 → 저장
   (System Events: 저장 패널 `splitter group 1`의 `pop up button 2`·`text field "별도 저장:"`·
   `button "저장"`; 같은 이름이 있으면 시트의 `button "대치"`).
5. 같은 세션에서 다시 `다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장해
   `HwpxFixtures/ms-word-script-strikethrough/document.hwpx`를 갱신한다.
6. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`의 기대값을 갱신한 뒤
   `swift test --filter "FixtureManifest|HwpxFixtureManifest|HwpxHwpEquivalence|FixtureRender|FixtureDecorationLineRender"`로
   검증한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6523`
- 생성일: 2026-10-02

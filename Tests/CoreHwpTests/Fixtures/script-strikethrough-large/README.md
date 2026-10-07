# script-strikethrough-large

`document.hwp`는 **한글 문서**(호환 문서 대상 프로그램 0, `HWP201X`)에 기본 크기 50–160pt의 보통·위
첨자·아래 첨자 취소선을 한 줄씩 나란히 둔 6문단을 실은 합성 HWPX를 한컴오피스 한글 12.30.0 (build 6523)에서
열어 2026-10-07에 `한글 문서 (*.hwp)`로 저장한 binary HWP fixture다. 한글이 이 문서에서 **위·아래 첨자 run의
취소선을 첨자로 옮겨진 베이스라인 위, 보통 글자 취소선 높이(0.35 × 기본 크기)의 89/140배**(⌊89 × 기본
크기(HWPUNIT) ÷ 400⌋ HWPUNIT)에 그리는 규칙(#258 — 첨자 글리프 축소 비율 0.64가 아니다, #179)의 실물 근거다.
같은 편집 세션에서 저장한 HWPX 쌍(`HwpxFixtures/script-strikethrough-large`)과 PDF 내보내기(1쪽)가 같은
문서이고, PDF 좌표가 렌더 핀의 오라클이다 (`HwpKitTests/FixtureDecorationLineRenderTests+ScriptLarge.swift`).
`script-decorations`(10pt)·`mixed-size-decorations`(M11, 기본 20pt)로는 두 배율의 차(0.015·0.03pt)가 한글
PDF의 장치 좌표(0.12pt) 안이라 가를 수 없어, 그 차가 0.075–0.24pt인 큰 글자로 만들었다.

글꼴은 `hwp2007-decorations`와 같이 한글 슬롯 **Apple SD 산돌고딕 Neo**, 라틴 슬롯 **Menlo**다 — 둘 다
macOS·iOS에 기본 탑재이고 결정론 resolver(`HwpFontResolver.testDeterministic`: Menlo + 한글 대체 Apple SD
Gothic Neo)가 같은 글꼴을 고르므로, 한글 PDF의 쪽 좌표를 어느 기기에서든 그대로 핀할 수 있다. 한글 문서의
선 자리는 글꼴과 무관하다 (#258 실측: 글꼴 10종이 같은 자리).

## 포함 기능

- 한 구역, 7문단(1쪽) — 첫 문단은 구역 정의만 있는 빈 문단이고, 이어 6문단이 표본마다 **보통 run +
  빈칸 2개 + 위 첨자 run + 빈칸 2개 + 아래 첨자 run** + 꼬리표(` #1`…` #6`, Menlo 5pt) + 문단 끝
  글자(꼬리표 글자 모양)로 온다. 선 색은 보통 청록 `#00FFFF`, 위 첨자 자홍 `#FF00FF`, 아래 첨자 초록
  `#00FF00`이고 빈칸은 장식 없는 Menlo 20pt다. 문단 모양은 왼쪽 정렬·줄 간격 비율 100%다.
  1. `xx` Menlo 50pt — 실선 취소선
  2. `x` Menlo 80pt — 실선 취소선
  3. `가` Apple SD 100pt — 실선 취소선
  4. `x` Menlo 100pt — 실선 **글자 가운데 밑줄**(밑줄 종류 `CENTER`)
  5. `x` Menlo 150pt — 실선 취소선
  6. `x` Menlo 160pt — 실선 취소선
- PreviewText/PreviewImage stream, BinData storage 없음

## 한글.app 실측 (같은 세션 PDF 내보내기, 쪽 위에서부터 pt)

| 문단 | 표본 | 베이스라인 | 보통 | 위 첨자 | 아래 첨자 |
|---|---|---:|---:|---:|---:|
| 1 | Menlo 50pt | 151.80 | 134.28 | 118.68 | 146.64 |
| 2 | Menlo 80pt | 227.28 | 199.20 | 174.24 | 219.00 |
| 3 | Apple SD 100pt | 324.24 | 289.20 | 258.00 | 314.04 |
| 4 | Menlo 100pt 가운데 밑줄 | 424.20 | 389.28 | 357.96 | 414.00 |
| 5 | Menlo 150pt | 566.76 | 514.20 | 467.40 | 551.40 |
| 6 | Menlo 160pt | 725.28 | 669.24 | 619.20 | 708.84 |

(선 중심 y. 첨자 글리프는 0.64배이고 위 첨자는 기본 크기의 0.44배 위, 아래 첨자는 0.12배 아래다 — 1번
위 첨자 글리프 베이스라인 129.72·아래 첨자 157.80, 6번 654.84·744.48.) 보통 글자 취소선은 베이스라인 위
0.35 × 기본 크기이고, 첨자 취소선은 **첨자로 옮겨진 베이스라인** 위 그 높이의 89/140배다 — 기본 크기의
0.2225배 (1번 위 첨자: 151.80 − 0.44 × 50 − 0.2225 × 50 = 118.675, 한글 118.68). 12선 모두 이 모형과
0.08pt 안이다 (한글 PDF의 베이스라인 기준). 0.64배(첨자 글리프 축소 비율)였다면 첨자 선이 기본 크기의
0.0015배만큼 높다 — 같은 기준으로 3번 위·아래 첨자 257.84·313.84, 5번 467.16·551.16, 6번 619.04·708.64다.
우리 렌더는 베이스라인을 줄 캐시의 연속값으로 두므로 쪽 좌표 차가 조금 다르다: 수정 후 12선 최대 0.105pt(1번 위
첨자), 0.64배로 그리면 문단마다 0.12–0.30pt(5번 위·아래 첨자 0.30)다. 글자 가운데
밑줄(4번)도 같은 자리다. 선 두께는 한글·우리 모두 글자 모양 기본 크기의 장치 단위 획이라 첨자도 보통과
같다 (#252 — 50pt 1.92·80pt 3.12·100pt 3.96·150pt 5.88·160pt 6.24pt).

## 재생성 절차

1. `HwpxFixtures/CharShape/document.hwpx`(대상 프로그램 `HWP201X`)를 풀어 `header.xml`의 라틴 글꼴 목록에
   `Menlo`를 더하고(`hh:fontface lang="LATIN"`의 `fontCnt` + 1), `hh:charPr id="0"`을 복제해 위 표본의 글자
   모양을 만든다 — `height`, `hh:fontRef`(한글·한자·일본어·기타·기호·사용자 슬롯 2 = Apple SD 산돌고딕 Neo,
   라틴 슬롯 = Menlo), `hh:strikeout@shape="SOLID"`·`@color` 또는 `hh:underline@type="CENTER"`·`@shape`·
   `@color`, 위·아래 첨자는 `</hh:charPr>` 바로 앞에 `<hh:supscript/>`·`<hh:subscript/>`. `hh:paraPr id="0"`을
   복제해 왼쪽 정렬 줄 간격 비율 100% 문단 모양을 만들고, `section0.xml`은 첫 문단(`hp:secPr`)만 남기고 위
   순서의 6문단을 `hp:linesegarray` **없이** 적는다 (한글이 새로 조판하게). 생성기는 로컬
   `probes/258/gen258fx.py`다. `mimetype`을 `ZIP_STORED` 첫 항목으로 다시 압축한다.
2. 그 HWPX를 `open -b com.hancom.office.hwp12.mac.general`로 연다.
3. `파일 > PDF로 저장하기...`로 같은 세션의 PDF를 내보낸다 (1쪽, A4).
4. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 파일명만 입력 → 저장
   (System Events: 저장 패널 `splitter group 1`의 `pop up button 2`·`text field "별도 저장:"`·
   `button "저장"`; 같은 이름이 있으면 시트의 `button "대치"`).
5. 같은 세션에서 다시 `다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장해
   `HwpxFixtures/script-strikethrough-large/document.hwpx`를 갱신한다.
6. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`의 기대값을 갱신한 뒤
   `swift test --filter "FixtureManifest|HwpxFixtureManifest|HwpxHwpEquivalence|FixtureRender|FixtureDecorationLineRender"`로
   검증한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6523`
- 생성일: 2026-10-07

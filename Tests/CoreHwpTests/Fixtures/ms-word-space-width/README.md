# ms-word-space-width

`document.hwp`는 **MS 워드 호환 문서**(호환 문서 대상 프로그램 2, `CT_MSWORD`)에 빈칸(U+0020) 폭 표본
6문단을 실은 합성 HWPX를 한컴오피스 한글 12.30.0 (build 6523)에서 열어 2026-10-03에 `한글 문서 (*.hwp)`로
저장한 binary HWP fixture다. 한글이 이 문서에서 **앞뒤가 모두 라틴 부류 글자인 빈칸만 라틴 글꼴의 고유
빈칸 폭으로**, 나머지(한글 이웃·줄 시작·연속 빈칸·`½` 이웃)는 한글 문서와 같은 고정 폭(한글 슬롯 글자 크기
× 0.5)으로 벌리는 규칙(#249)의 실물 근거다. 같은 편집 세션에서 저장한 HWPX 쌍
(`HwpxFixtures/ms-word-space-width`)과 PDF 내보내기(1쪽)가 같은 문서이고, PDF의 글자 원점이 렌더 핀의
오라클이다 (`HwpKitTests/FixtureSpaceWidthTests.swift`). 한글 문서 쪽 대조군은 `space-width`다.

글꼴은 `space-width`와 같이 한글 슬롯 **Apple SD 산돌고딕 Neo**, 라틴 슬롯 **Menlo**다 — 둘 다 macOS·iOS에
기본 탑재이고 결정론 resolver(`HwpFontResolver.testDeterministic`: Menlo + 한글 대체 Apple SD Gothic Neo)가
같은 글꼴을 고르며, 문단마다 한 줄이라 줄 시작이 같으므로 한글 PDF의 쪽 좌표를 어느 기기에서든 그대로 핀할
수 있다.

## 포함 기능

- 한 구역, 7문단(1쪽) — 첫 문단은 구역 정의와 제목 `#249 ms-word-space-width`(함초롬바탕 10pt)이고, 이어
  6문단이 표본마다 **표본 run** + 꼬리표(` #1`…` #6`, 함초롬바탕 5pt) + 문단 끝 글자(꼬리표 글자 모양)로
  온다. 표본은 기본 크기 20pt, 문단 모양은 왼쪽 정렬·줄 간격 비율 160%다. 아래 "한글 / 라틴"은 슬롯 상대
  크기다.

  | 문단 | 텍스트 | 글자 모양 (한글 / 라틴) | 표본이 가르는 것 |
  |---|---|---|---|
  | 1 | `ab cd 가나 ef` | 50% / 100% | 라틴 사이만 Menlo 고유 폭, 한글 앞뒤는 고정 폭 |
  | 2 | ` ab  cd` | 50% / 100% | 줄 시작 빈칸·연속 빈칸은 고정 폭 |
  | 3 | `ab, cd ½ ef` | 100% / 50% | 구두점 뒤 빈칸은 라틴 고유 폭, `½` 앞뒤는 고정 폭 |
  | 4 | `ab` + ` cd` | 같은 폭의 다른 글자 모양 run(한자 슬롯만 함초롬바탕 70%) | run 경계를 넘은 라틴 이웃도 고유 폭 |
  | 5 | `가나 ab cd` | 50% / 100%, **글꼴에 어울리는 빈칸** | 한글 문서와 같다 |
  | 6 | `ab`·`cd`·`ef` | 50% / 100% | **묶음 빈칸**(`hp:nbSpace`)·**고정폭 빈칸**(`hp:fwSpace`) |

- 빈칸 표본은 모두 장식이 없고, 꼬리표·문단 끝 글자를 5pt로 두어 줄 상자에 끼어들지 않게 했다.
- `HWPTAG_COMPATIBLE_DOCUMENT` 대상 프로그램 2
- PreviewText/PreviewImage stream, BinData storage 없음

## 한글.app 실측 (같은 세션 PDF 내보내기, 쪽 왼쪽에서 pt)

한글 글자(Apple SD 산돌고딕 Neo 10pt)의 진행 폭은 8.64pt이고, Menlo 글자는 0.6em(10pt 6.02pt·20pt
12.04pt)이다. 빈칸 폭은 이웃 글자 원점 간격에서 앞 글자 진행 폭을 뺀 값이다 (PDF 원점이 0.12pt 장치
단위로 양자화돼 ±0.06pt 흔들린다).

| 문단 | 베이스라인 | 글자 원점 | 빈칸 폭 |
|---|---:|---|---|
| 1 | 148.44 | a 85.08 · b 97.08 · c 121.20 · d 133.20 · 가 150.24 · 나 158.88 · e 172.56 · f 184.56 | 라틴 사이 12pt (Menlo 20pt 고유 폭), 한글 앞뒤 5pt |
| 2 | 198.24 | a 90.12 · b 102.12 · c 124.20 · d 136.20 | 줄 시작 5pt, 연속 빈칸 5pt + 5pt |
| 3 | 246.72 | a 85.08 · b 91.08 · , 97.20 · c 109.20 · d 115.32 · ½ 131.28 · e 147.36 · f 153.36 | 구두점 뒤 6pt (Menlo 10pt 고유 폭), `½` 앞뒤 10pt (한글 20pt × 0.5) |
| 4 | 295.20 | a 85.08 · b 97.08 · c 121.20 · d 133.20 | 12pt (Menlo 20pt 고유 폭) |
| 5 | 343.56 | 가 85.08 · 나 93.72 · a 108.36 · b 120.48 · c 144.48 · d 156.60 | 한글 뒤 6pt (Menlo 0.6em × 10pt), 라틴 뒤 12pt (× 20pt) |
| 6 | 393.48 | a 85.08 · b 97.08 · c 114.12 · d 126.24 · e 140.76 · f 152.76 | 묶음 빈칸 5pt, 고정폭 빈칸 2.5pt |

문단 2·5·6의 글자 원점은 `space-width`의 같은 텍스트·글자 모양 문단(3·5·7번)과 같다 — 호환 문서에서
달라지는 것은 앞뒤가 라틴 부류 글자인 빈칸이다. 수정 전 렌더(빈칸 = 라틴 슬롯 글자 크기의 0.5em, MS 워드 호환 문서는 늘 글꼴 폭)는 이 쌍과
`space-width` 쌍의 문단 13개 중 11개가 6.0~21.1pt 어긋났고, 수정 뒤에는 HWP·HWPX 두 저장본 모두 0.18pt
안이다 (핀 허용 0.25pt).

## 재생성 절차

1. `HwpxFixtures/CharShape/document.hwpx`를 풀어 `header.xml`의 글꼴 목록에 Apple SD 산돌고딕 Neo·Menlo를
   더하고(모든 언어의 `fontCnt`를 함께 올린다), `hh:charPr id="0"`을 복제해 위 표본의 글자 모양을 만든다 —
   `height="2000"`, `hh:fontRef`(한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo·나머지 함초롬바탕),
   `hh:relSz`(한글·라틴 50/100 또는 100/50, 4번 둘째 run은 한자 70), `useFontSpace`(5번 `1`). 꼬리표는
   `height="500"`, 제목은 `height="1000"`의 함초롬바탕 글자 모양이다. `hh:compatibleDocument@targetProgram`을
   `MS_WORD`로 바꾼다. `hh:paraPr id="0"`을 복제해 왼쪽 정렬 줄 간격 비율 160% 문단 모양을 만들고,
   `section0.xml`은 첫 문단(`hp:secPr` + 제목)과 위 순서의 6문단을 `hp:linesegarray` **없이** 적는다 (한글이
   새로 조판하게). 6번은 `ab<hp:nbSpace/>cd<hp:fwSpace/>ef`다. 생성기는 로컬 `probes/249/gen249fx.py`다.
   `mimetype`을 `ZIP_STORED` 첫 항목으로 다시 압축한다.
2. 그 HWPX를 `open -b com.hancom.office.hwp12.mac.general`로 연다.
3. `파일 > PDF로 저장하기...`로 같은 세션의 PDF를 내보낸다 (1쪽, A4).
4. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 파일명만 입력 → 저장
   (System Events: 저장 패널 `splitter group 1`의 `pop up button 2`·`text field "별도 저장:"`·
   `button "저장"`; 같은 이름이 있으면 시트의 `button "대치"`).
5. 같은 세션에서 다시 `다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장해
   `HwpxFixtures/ms-word-space-width/document.hwpx`를 갱신한다.
6. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`의 기대값을 갱신한 뒤
   `swift test --filter "FixtureManifest|HwpxFixtureManifest|HwpxHwpEquivalence|FixtureRender|FixtureSpaceWidth"`로
   검증한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6523`
- 생성일: 2026-10-03

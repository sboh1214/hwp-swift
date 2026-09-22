# hwp2007-decorations

`document.hwp`는 **한글 2007 호환 문서**(호환 문서 대상 프로그램 1, `CT_HWP200X`)에 글자
장식선을 실은 HWPX를 한컴오피스 한글 12.30.0 (build 6446)에서 열어 2026-09-22에
`한글 문서 (*.hwp)`로 저장한 binary HWP fixture다. 한글 2007 호환 문서에서 한글이 장식선을
**크기와 무관한 고정 두께**로 놓고 밑줄은 한글 문서와 같은 가장자리에 얹는 규칙(#210)의
실물 근거이며, 같은 편집 세션에서 저장한 HWPX 쌍(`HwpxFixtures/hwp2007-decorations`)과
PDF 내보내기 좌표가 렌더 핀의 오라클이다.

글꼴은 한글 슬롯 **Apple SD 산돌고딕 Neo**, 라틴 슬롯 **Menlo**로 `compat-decorations`와
같다 — 둘 다 macOS·iOS 기본 탑재이고 결정론 resolver(`HwpFontResolver.testDeterministic`:
Menlo + 한글 대체 Apple SD Gothic Neo)가 같은 글꼴을 고르므로, 한글 PDF의 좌표를 어느
기기에서든 그대로 핀할 수 있다. 크기 축(10·20·40·60pt)을 실은 이유는 **두께가 크기에
비례하는지**를 한 문서 안에서 가르기 위해서다.

## 포함 기능

- 한 구역, 10문단 — 첫 문단은 구역 정의를 품은 제목(`한글 2007 호환 장식선`, 10pt,
  장식 없음)이고 나머지 9문단은 `태그 가나Ag` 꼴의 한글·라틴 글자를 한 글자 모양으로 싣는다:
  1. `U10 가나Ag` 10pt — 글자 아래 밑줄(초록 `#00FF00`)
  2. `U20 가나Ag` 20pt — 글자 아래 밑줄
  3. `U40 가나Ag` 40pt — 글자 아래 밑줄
  4. `U60 가나Ag` 60pt — 글자 아래 밑줄
  5. `T40 가나Ag` 40pt — 글자 위 밑줄(파랑 `#0000FF`)
  6. `T60 가나Ag` 60pt — 글자 위 밑줄
  7. `S10 가나Ag` 10pt — 취소선(청록 `#00FFFF`, 한글이 '글자 가운데' 밑줄 + 취소선 비트의
     레거시 이중 기록으로 저장한다)
  8. `S40 가나Ag` 40pt — 취소선
  9. `C40 가나Ag` 40pt — 글자 가운데 밑줄(주황 `#FF8000`)
- 글자 모양 18개(한컴 기본 모양 + 위 9종 + 제목 2종), `HWPTAG_COMPATIBLE_DOCUMENT`
  대상 프로그램 1
- PreviewText/PreviewImage stream, BinData storage 없음

## 한글.app 실측 (같은 세션 PDF 내보내기, 베이스라인 기준, 위가 양수)

| 문단 | 장식선 | 글자 크기 | 선 중심 | 선 두께 | 크기 대비 중심 |
|---|---|---:|---:|---:|---:|
| 1 | 글자 아래 밑줄 | 10pt | −1.68pt | 0.36pt | −0.168em |
| 2 | 글자 아래 밑줄 | 20pt | −3.24pt | 0.36pt | −0.162em |
| 3 | 글자 아래 밑줄 | 40pt | −6.12pt | 0.36pt | −0.153em |
| 4 | 글자 아래 밑줄 | 60pt | −9.12pt | 0.36pt | −0.152em |
| 5 | 글자 위 밑줄 | 40pt | +34.20pt | 0.36pt | +0.855em |
| 6 | 글자 위 밑줄 | 60pt | +51.18pt | 0.36pt | +0.853em |
| 7 | 취소선 | 10pt | +3.48pt | 0.36pt | +0.348em |
| 8 | 취소선 | 40pt | +14.04pt | 0.36pt | +0.351em |
| 9 | 글자 가운데 밑줄 | 40pt | +14.04pt | 0.36pt | +0.351em |

두께는 네 크기 전부 **0.36pt로 같다** — 한글 문서·MS 워드 호환 문서의 크기 비례 두께와
갈리는 자리다. 밑줄 중심은 아래 0.15em·위 0.85em 가장자리에서 두께의 절반만큼 바깥으로
밀린 자리(10·60pt는 0.15em/0.85em + 0.18pt에 정확히 맞고, 20·40pt는 ±0.06pt 안에서
어긋난다)이고, 취소선·글자 가운데 밑줄은 0.35em 자리다. 쪽수는 1쪽이다.

## 재생성 절차

1. `HwpxFixtures/CharShape/document.hwpx`를 풀어 `header.xml`의 `hh:compatibleDocument`를
   `targetProgram="HWP200X"`로 바꾸고, `hh:fontfaces`의 LATIN 슬롯에 `Menlo`를 더한 뒤
   `hh:charPr id="0"`을 복제해 한글 슬롯 Apple SD 산돌고딕 Neo · 라틴 슬롯 Menlo로
   글자 아래 밑줄(10·20·40·60pt)·글자 위 밑줄(40·60pt)·취소선(10·40pt)·글자 가운데
   밑줄(40pt) 글자 모양 9종을 만든다. `section0.xml`은 제목 문단(`hp:secPr`)에 이어
   그 9종을 문단마다 하나씩 `hp:linesegarray` **없이** 적는다 (한글이 새로 조판하게).
   `mimetype`을 `ZIP_STORED` 첫 항목으로 다시 압축한다.
2. 그 HWPX를 `open -b com.hancom.office.hwp12.mac.general`로 연다.
3. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 파일명만
   입력 → 저장 (System Events: 저장 패널 `splitter group 1`의 `pop up button 2`·
   `text field "별도 저장:"`·`button "저장"`; 같은 이름이 있으면 시트의 `button "대치"`).
4. 같은 세션에서 다시 `다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** →
   저장해 `HwpxFixtures/hwp2007-decorations/document.hwpx`를 갱신한다.
5. `파일 > PDF로 저장하기...`로 오라클 PDF를 내보내 벡터 좌표(PyMuPDF `rawdict`의
   글자 `origin`, `get_drawings()`의 색 선)를 읽는다.
6. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`의 기대값을
   갱신한 뒤
   `swift test --filter "FixtureManifest|HwpxFixtureManifest|HwpxHwpEquivalence"`로
   검증한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-22

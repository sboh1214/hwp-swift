# script-decorations

`document.hwp`는 위/아래 첨자와 장식선(취소선·글자 가운데 밑줄·글자 아래 밑줄·글자
위 밑줄)·글자 위치를 조합한 합성 HWPX를 한컴오피스 한글 12.30.0 (build 6446)에서
열어 2026-09-15에 `한글 문서 (*.hwp)`로 저장한 binary HWP fixture다. 첨자 run의
장식선이 어디에 그려지는지(#179)의 실물 근거이며, 같은 편집 세션에서 저장한 HWPX
쌍(`HwpxFixtures/script-decorations`)과 PDF 내보내기 좌표가 렌더 핀의 오라클이다
(`HwpKitTests/FixtureDecorationLineRenderTests+Script.swift`).

## 포함 기능

- 한 구역, 12문단 — 첫 문단은 구역 정의만 있는 빈 문단이고 나머지 11문단은
  `기준 Ag ` (검정 10pt 함초롬바탕) + `대상 Ag` (빨강, 조합 적용) + ` <설명>` (검정)
  세 run이다. 대상 run의 조합은 문단 순서대로:
  1. 위 첨자 + 취소선 (청록 `#00FFFF`)
  2. 아래 첨자 + 취소선
  3. 위 첨자 + 밑줄 '글자 가운데' (자홍 `#FF00FF`)
  4. 아래 첨자 + 밑줄 '글자 가운데'
  5. 위 첨자 + 밑줄 '글자 아래' (초록 `#00FF00`)
  6. 아래 첨자 + 밑줄 '글자 아래'
  7. 위 첨자 + 밑줄 '글자 위'
  8. 아래 첨자 + 밑줄 '글자 위'
  9. 글자 위치 50 + 취소선 (첨자 없음 — 대조군)
  10. 위 첨자 + 글자 위치 50 + 취소선
  11. 위 첨자 + 글자 위치 50 + 밑줄 '글자 아래'
- 글자 모양 19개 — 대상 run의 `charShape[8…18]` 속성(표 33)은
  `0x48008 · 0x50008 · 0x8008 · 0x10008 · 0x8004 · 0x10004 · 0x800C · 0x1000C ·
  0x40008 · 0x48008 · 0x8004`. 취소선만 켠 첨자 글자 모양(1·2·10)에도 한글이 밑줄
  종류 2(가운데)를 함께 적는다 — `line-shapes`에서 본 이중 기록과 같다.
- PreviewText/PreviewImage stream, BinData storage 없음

## 한글.app 실측 (같은 세션 PDF 내보내기, 쪽 위에서부터 pt)

문단 k(1부터)의 베이스라인은 줄 캐시대로 107.7 + 16k다. 선의 중심 y:

| k | 조합 | 선 y | 해석 |
|---|---|---:|---|
| 1 | 위 첨자 취소선 | 117.12 | 옮겨진 베이스라인(4.32~4.44 위) + 0.35 × 6.36pt |
| 2 | 아래 첨자 취소선 | 138.72 | 옮겨진 베이스라인(1.20 아래) + 0.35 × 6.36pt |
| 3 | 위 첨자 가운데 밑줄 | 149.16 | 취소선과 같은 규칙 |
| 4 | 아래 첨자 가운데 밑줄 | 170.76 | 취소선과 같은 규칙 |
| 5 | 위 첨자 아래 밑줄 | 189.48 | 원래 베이스라인 − 0.17 × 10pt (첨자 무관) |
| 6 | 아래 첨자 아래 밑줄 | 205.44 | 원래 베이스라인 − 0.17 × 10pt |
| 7 | 위 첨자 위 밑줄 | 211.08 | 원래 베이스라인 + 0.87 × 10pt (첨자 무관) |
| 8 | 아래 첨자 위 밑줄 | 227.04 | 원래 베이스라인 + 0.87 × 10pt |
| 9 | 글자 위치 50 취소선 | 248.28 | 원래 베이스라인 + 0.35 × 10pt (글리프만 5.04 아래) |
| 10 | 위 첨자 + 글자 위치 50 취소선 | 261.12 | 1과 같은 자리 — 글자 위치 몫은 안 따라감 |
| 11 | 위 첨자 + 글자 위치 50 아래 밑줄 | 285.48 | 원래 베이스라인 − 0.17 × 10pt |

선 두께는 11개 전부 0.36pt(= 10pt × 0.04, 첨자 run도 본문 두께)다. 첨자 글리프는
6.36pt로 위 첨자가 4.44pt 위, 아래 첨자가 1.20pt 아래에 놓인다 (함초롬바탕·Apple SD
산돌고딕 Neo 두 글꼴, 10·20pt에서 같은 비율).

## 재생성 절차

1. `HwpxFixtures/CharShape/document.hwpx`를 풀어 `header.xml`의 `hh:charPr id="6"`
   (함초롬바탕 10pt)을 복제해 위 11조합의 글자 모양을 만들고(`textColor="#FF0000"`,
   `hh:offset` 50, `hh:underline type`/`hh:strikeout shape`, 끝에 `<hh:supscript/>` 또는
   `<hh:subscript/>`), `section0.xml`은 첫 문단(`hp:secPr`)만 남긴 뒤 위 순서의 11문단을
   `hp:linesegarray` **없이** 적는다 (한글이 새로 조판하게). `mimetype`을 `ZIP_STORED`
   첫 항목으로 다시 압축한다.
2. 그 HWPX를 `open -b com.hancom.office.hwp12.mac.general`로 연다.
3. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 파일명만
   입력 → 저장 (System Events: 저장 패널 `splitter group 1`의 `pop up button 2`·
   `text field 2`·`button "저장"`).
4. 같은 세션에서 다시 `다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** →
   저장해 `HwpxFixtures/script-decorations/document.hwpx`를 갱신한다.
5. `파일 > PDF로 저장하기...`로 오라클 PDF를 내보내 벡터 좌표(PyMuPDF `rawdict`의
   글자 `origin`, `get_drawings()`의 색 선)를 읽는다.
6. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`의
   payload prefix/suffix·`charShapePropertyRawValues`를 갱신한 뒤
   `swift test --filter "FixtureManifestTests|HwpxHwpEquivalenceTests|FixtureDecorationLineRenderTests"`를
   실행한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-15

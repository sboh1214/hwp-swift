# paragraph-end-char-size

`document.hwp`는 **문단 끝 글자**(CR, 코드 13)의 글자 모양 크기가 본문과 다른 문단들을 여러
조건으로 실은 합성 HWPX를 한컴오피스 한글 12.30.0 (build 6446)에서 열어 2026-09-21에
`한글 문서 (*.hwp)`로 저장한 binary HWP fixture다. 문단 끝 글자의 크기가 문단 마지막 줄의 줄
상자와 비율 줄 간격 여분에 드는 규칙(#206)의 실물 근거이며, 한글이 저장한 줄 캐시
(`PARA_LINE_SEG`의 `lineHeight`·`baselineDistance`·`lineSpacing`)와 같은 편집 세션에서 저장한
HWPX 쌍(`HwpxFixtures/paragraph-end-char-size`)·PDF 내보내기 좌표가 렌더 핀의 오라클이다
(`HwpKitTests/FixtureParagraphEndCharSizeTests.swift` — 줄 캐시를 지우고 다시 조판한 줄이 캐시로
놓인 줄과 같은 자리인지 본다).

## 포함 기능

- 한 구역, 최상위 49문단(5쪽) — 첫 문단은 구역 정의 + `#206 fixture`(함초롬바탕 10pt)이고,
  본문 문단은 `<태그> …`(함초롬바탕, 줄 간격 160%가 기본) 뒤에 글자 모양이 다른 빈 run으로
  문단 끝 글자의 글자 모양을 준 것이다. `after` 문단(10pt·CR 10pt)이 앞 문단의 전진량을 드러낸다.
  - `A1`~`A10`: 10pt 본문 + 16pt CR 한 줄·여러 줄, 16pt 본문 + 10pt CR 한 줄·여러 줄, 10pt + 40pt CR
  - `B1`~`B10`: 줄 간격 비율 100%·고정 30pt·여백만 5pt·최소 12pt·최소 20pt (`B9`부터 새 쪽)
  - `C1`~`C6`: CR 글자 모양 상대 크기 50%, Apple SD 산돌고딕 Neo, 문단 위/아래 간격 10pt
  - `D1`~`D6`: 한 줄 끝(코드 10) 조합 — 10pt run의 한 줄 끝 + 빈 마지막 줄, 16pt run의 한 줄
    끝, 한 줄 끝 뒤 둘째 줄
  - `E1`·`E3`(빈 문단): CR 16pt만, 빈 run 둘(10pt → 16pt)
  - `F1`·`F3`·`F5`: 글자처럼 취급 1칸 표(30pt·8pt·20pt, 마커 글자 모양 10pt) + 16pt CR —
    `F1`은 `noori` 2번째 문단 꼴(마커만, 170%)
  - `G1 host`: 자리 차지 1칸 표(폭 300pt) 셀 안에 `G1 cell 10+CR16`·`G1 cell after` (새 쪽)
  - `H1`: 10·20·10pt 본문 + 16pt CR
  - `T1 걸침`: 새 쪽에서 시작해 한 쪽(41줄)을 넘기는 10pt 문단 + 40pt CR — 앞 조각의 끝 줄은
    CR 크기를 받지 않고 마지막 줄만 40pt 상자다
  - `T2 after`·`Z 끝`: 10pt 종결 문단
- 글자 모양 13개(한글이 사용 순으로 재번호), 문단 모양 27개, 테두리/배경 3개, 표 4개
- PreviewText/PreviewImage stream, BinData 없음

## 한글.app 실측 (저장 줄 캐시, pt)

`vertsize`(줄 상자)·`baseline`(상자 상단 → 베이스라인)·`spacing`(비율 여분)이고 PDF 베이스라인은
본문 상단 99.2 + `vertpos` + `baseline`과 0.10pt(한글 PDF의 0.12pt 장치 양자화) 안에서 같다.
규칙: **문단의 마지막 줄** 상자 = max(글자 run 기본 크기, CR 기본 크기, 개체 높이), 비율 여분
기준 = max(글자 run 기본 크기, CR 기본 크기), 베이스라인 = 0.85 × 상자.

| 문단 | 줄 | `vertsize` | `baseline` | `spacing` | 규칙 |
|---|---|---:|---:|---:|---|
| A1 (10 + CR16) | 1 | 16 | 13.6 | 9.6 | CR이 상자·여분 기준 |
| A3 (10 여러 줄 + CR16) | 1~4 / 5 | 10 / 16 | 8.5 / 13.6 | 6 / 9.6 | 마지막 줄만 |
| A5·A7 (16 + CR10) | 전부 | 16 | 13.6 | 9.6 | 최댓값 |
| A9 (10 + CR40) | 1 | 40 | 34 | 24 | |
| B1 100% | 1 | 16 | 13.6 | 0 | |
| B3 고정 30 | 1 | 16 | 13.6 | 14 | 전진량 30 |
| B5 여백만 5 | 1 | 16 | 13.6 | 5 | 16 + 5 |
| B7 최소 12 · B9 최소 20 | 1 | 16 | 13.6 | 0 · 4 | max(16, v) |
| C1 rel50 · C3 Apple SD | 1 | 16 | 13.6 | 9.6 | 기본 크기, 글꼴 무관 |
| D1 (10 + LF(10pt) + CR16) | 1 / 2 | 16 / 16 | **8.5** / 13.6 | **6** / 9.6 | 한 줄 끝 줄은 CR 크기 없음 (`textheight` 10) |
| D3 (10 + LF(16pt run) + CR16) | 1 / 2 | 16 / 16 | 13.6 / 13.6 | 9.6 / 9.6 | 한 줄 끝 글자 자신의 크기 |
| D5 (10 + LF + "둘째 줄" + CR16) | 1 / 2 | 16 / 16 | 8.5 / 13.6 | 6 / 9.6 | |
| E1·E3 (빈 문단) | 1 | 16 | 13.6 | 9.6 | CR 글자 모양 (E3는 마지막 빈 run) |
| F1 (30pt 표 마커 10 + CR16, 170%) | 1 | 30 | 25.5 | 11.2 | `noori` 2번째 문단과 같다 |
| F3 (8pt 표 + CR16) | 1 | 16 | 13.6 | 9.6 | CR이 상자를 정한다 |
| F5 (20pt 표 + CR16) | 1 | 20 | 17 | 9.6 | 상자는 개체, 여분 기준은 CR 16 |
| G1 cell (셀 안 10 + CR16) | 1 | 16 | 13.6 | 9.6 | 컨테이너도 같다 |
| H1 (10·20·10 + CR16) | 1 | 20 | 17 | 12 | |
| T1 (10 × 57줄 + CR40) | 1~56 / 57 | 10 / 40 | 8.5 / 34 | 6 / 24 | 쪽 경계 조각 끝 줄(41째)도 10 |

`D1`·`D5`의 한 줄 끝으로 끝난 첫 줄은 `vertsize`만 16이고 `textheight`·`baseline`·`spacing`은
10pt 기준(전진량 16, PDF 베이스라인도 8.5)이다 — 배치는 10pt 상자다.

## 재생성 절차

1. `HwpxFixtures/CharShape/document.hwpx`를 풀어 `header.xml`에 함초롬바탕 10·16·20·40pt·상대
   크기 50%·Apple SD 16pt 글자 모양과 줄 간격 종류별 문단 모양, 실선 테두리를 덧붙이고,
   `section0.xml`을 위 문단들로 갈아 끼운다 (문단 끝 글자의 글자 모양은 문단 마지막에 그
   글자 모양의 빈 run `<hp:run charPrIDRef="N"><hp:t/></hp:run>`으로, `hp:linesegarray` 없음 —
   한글이 새로 조판한다).
2. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 그 HWPX를 열어 `파일 > PDF로 저장하기...`로 실측 PDF를 내고,
   `파일 > 다른 이름으로 저장하기...` → **한글 문서 (*.hwp)**, 같은 세션에서 다시 → **한글
   표준 문서 (*.hwpx)**로 저장한다 (System Events 접근성 자동화).
3. `.hwp`를 이 디렉터리의 `document.hwp`로, `.hwpx`를 `HwpxFixtures/paragraph-end-char-size/
   document.hwpx`로 복사하고 두 `manifest.json`의 기대값을 갱신한 뒤 `swift test --filter Fixture`를
   돌린다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-21

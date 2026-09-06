# numbering-sequence

`document.hwp`는 `plain-text-minimal`의 `document.hwp` 사본을 한컴오피스 한글
12.30.0 (build 6446)에서 열어 개요·문단 번호·구역·표를 섞어 입력하고 2026-09-06에
저장한 binary HWP fixture다. 문단 번호·개요 번호 **생성 규칙의 실측 오라클**이다
(#153) — 한글.app이 그린 라벨은 같은 세션에서 `편집 > 모두 선택` · `복사하기`로
복사한 텍스트(한글은 자동 번호 라벨을 복사 텍스트에 넣는다)로 받아
`Tests/HwpKitCoreTests/HwpParagraphNumberingFixtureTests`가 문단마다 대조한다.

## 포함 기능

- 구역 3개, 문단 6 + 9 + 5개(표 셀 2개 별도). 한글.app이 그린 라벨(복사 텍스트):

  | 구역 | 문단 | 한글 라벨 | 뜻 |
  |---|---|---|---|
  | 1 | Outline one / Outline one-one | `1.` / `가.` | 개요 1·2수준 (정의 1) |
  | 1 | Numbered A one / two, Body between, (구역 2) Numbered A three | `1.` `2.` — `3.` | 문단 번호 목록(정의 2)은 본문 문단과 **구역 경계**를 지나도 잇는다 |
  | 2 | Outline two / Outline two-one-one | `나.` / `가)` | 구역 나누기가 만든 정의 4(시작 번호 0)는 앞 구역의 개요 번호를 **이어 받는다** |
  | 2 | Numbered B five / five-x-one / five-one / six / Numbered A continue | `1.` `1)` `나.` `2.` `3.` | 정의 3(`start=5`, 수준별 [1…])은 **배열이 이겨** 1부터; 3수준을 건너뛰면 2수준은 시작 번호로 매겨진 것으로 쳐 다음 2수준이 `나.` |
  | 2 | Outline three | `2.` | 정의 4의 1수준이 앞 구역의 `1.` 뒤를 잇는다 |
  | 3 | Section three outline | `7.` | 개요 번호 모양 › 새 번호로 시작 7 → 정의 5(`start=7`, 배열 [7, 1, …]) |
  | 3 | Section three numbered / (표를 품은 빈 문단) / Cell one / Cell two / After table numbered / Numbered restart nine | `4.` `5.` `9.` `10.` `6.` `11.` | 정의 3의 목록은 표 셀의 정의 6(`start=9`) 목록을 사이에 두고 `4.`·`5.`·`6.`으로 잇고, 정의 6은 `9.`·`10.`·`11.` — **정의마다 목록이 하나**이며 표를 품은 문단이 셀보다 먼저다 |

- 문단 번호 정의 6개: 1(기본, 구역 1 개요) · 2(문단 번호 적용이 만든 목록 A, 시작
  번호 0) · 3(새 번호 목록 시작 5로 만든 뒤 모양을 바꾼 목록 B — `start=5`가 남고
  수준별 배열은 [1…]) · 4(구역 나누기가 만든 구역 2 개요 정의, 시작 번호 0) ·
  5(구역 3 개요, `start=7`·배열 [7…]) · 6(셀 목록, `start=9`·배열 [9…])
- 표 1×2 (셀 문단에 문단 번호 적용), PreviewText·PreviewImage stream, BinData 없음

## 재생성 절차

1. `Tests/CoreHwpTests/Fixtures/plain-text-minimal/document.hwp` **사본**을 한컴오피스
   한글에서 연다 (열람만으로 원본이 재기록되므로 사본 필수).
2. 첫 문단 끝에서 Return 뒤 "Outline one" `서식 > 개요 적용/해제`, "Outline one-one"
   `한 수준 감소`, "Numbered A one" `개요 적용/해제`(해제) + `문단 번호 적용/해제`,
   "Numbered A two", "Body between" `문단 번호 적용/해제`(해제), "Numbered A three"
   `문단 번호 적용/해제`, "Outline two" `문단 번호 적용/해제`(해제) + `개요 적용/해제`
   (앞 개요 수준을 물려받아 2수준), "Outline two-one-one" `한 수준 감소` 2회(4수준),
   "Numbered B five" `개요 적용/해제`(해제) + `서식 > 문단 번호 모양...`에서 모양
   `1. 1.1. 1.1.1.` · 새 번호 목록 시작 · 1수준 시작 번호 5 → 설정, "Numbered B
   five-x-one" `한 수준 감소` 2회, "Numbered B five-one" `한 수준 증가`, "Numbered B
   six" `한 수준 증가`, "Numbered A continue" `문단 번호 모양...`에서 모양 `1. 가. 1)
   가)` · 앞 번호 목록에 이어 → 설정(목록 B 전체의 모양이 바뀐다).
3. "Body between" 끝에서 `쪽 > 구역 나누기`(구역 2는 "Numbered A three"부터), 문서 끝에서
   "Outline three" `문단 번호 적용/해제`(해제) + `개요 적용/해제` + `한 수준 증가` 3회.
4. `쪽 > 구역 나누기` 뒤 "Section three outline"(개요 1수준을 물려받음) `서식 > 개요 번호
   모양...`에서 새 번호로 시작 · 1수준 시작 번호 7 · 적용 범위 현재 구역 → 설정,
   "Section three numbered" `개요 적용/해제`(해제) + `문단 번호 적용/해제`.
5. `표 > 표 > 표 만들기...` 줄 1 · 칸 2 → 만들기, 셀에 "Cell one" `문단 번호 적용/해제`,
   Tab, "Cell two" `문단 번호 적용/해제`. 표 뒤 빈 번호 문단에 "After table numbered",
   Return, "Numbered restart nine" `문단 번호 모양...`에서 새 번호 목록 시작 · 1수준
   시작 번호 9 → 설정.
6. `파일 > 다른 이름으로 저장하기...`로 `한글 문서 (*.hwp)` 저장, 같은 세션에서 `한글 표준
   문서 (*.hwpx)`로도 저장해 `HwpxFixtures/numbering-sequence/document.hwpx`를 갱신한다.
7. 저장된 파일을 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`의 기대값을
   갱신한 뒤 `swift test --filter "FixtureManifestTests|NumberingStartingNumberTests|HwpxHwpEquivalenceTests|HwpParagraphNumbering"`을
   실행한다.
8. `편집 > 모두 선택` · `편집 > 복사하기` 뒤 `pbpaste`로 라벨을 받아 위 표와 대조한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6446`
- 생성일: 2026-09-06

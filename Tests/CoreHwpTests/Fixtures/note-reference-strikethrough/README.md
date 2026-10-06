# note-reference-strikethrough

`document.hwp`는 **MS 워드 호환 문서**(호환 문서 대상 프로그램 2, `CT_MSWORD`)에 취소선·글자 가운데
밑줄이 걸린 글자 사이에 각주·미주 참조 번호를 둔 7문단을 실은 합성 HWPX를 한컴오피스 한글 12.30.0
(build 6523)에서 열어 2026-10-06에 `한글 문서 (*.hwp)`로 저장한 binary HWP fixture다. 한글이 각주·미주
참조 번호(0.75배 글꼴·0.21em 올림)에 걸린 **취소선·글자 가운데 밑줄을 번호가 놓인 글자 모양의 자리·
두께에** 그리고(위 첨자 글자 모양 안 번호는 그 첨자 선), 번호를 **앞뒤 글자와 따로 된 글자 모양 run으로**
그리는 규칙(#256)의 실물 근거다. 같은 편집 세션에서 저장한 HWPX 쌍
(`HwpxFixtures/note-reference-strikethrough`)과 PDF 내보내기(3쪽 — 본문 2쪽 + 미주 1쪽)가 같은 문서이고,
PDF 좌표가 렌더 핀의 오라클이다 (`HwpKitTests/FixtureDecorationLineRenderTests+NoteReference.swift`).

글꼴은 `compat-decorations`·`ms-word-script-strikethrough`와 같이 한글 슬롯 **Apple SD 산돌고딕 Neo**,
나머지 슬롯 **Menlo**다 — 둘 다 macOS·iOS에 기본 탑재이고 결정론 resolver
(`HwpFontResolver.testDeterministic`: Menlo + 한글 대체 Apple SD Gothic Neo)가 같은 글꼴을 고르므로, 한글
PDF의 쪽 좌표를 어느 기기에서든 그대로 핀할 수 있다.

## 포함 기능

- 한 구역, 7문단(3쪽 — 본문 2쪽 + 미주 1쪽). 첫 문단이 구역 정의를 품고, 문단마다 표본 run 뒤에
  꼬리표(` #1`…` #7`, Menlo 5pt, 장식 없음)가 온다. 선 색은 취소선 빨강 `#FF0000`, 가운데 밑줄 자홍
  `#FF00FF`이다. 문단 모양은 양쪽 정렬·줄 간격 비율 160%다.
  1. `xx` + 각주 + `xx` — Menlo 20pt 실선 취소선. 각주 1의 내용은 같은 글자 모양의 ` xx`라 각주 내용
     첫머리의 위 첨자 번호에도 선이 걸린다.
  2. `xx` + 미주 + `xx` — Menlo 40pt 실선 취소선
  3. `xx` + 각주 + `xx` — Menlo 20pt 실선 **글자 가운데 밑줄**(밑줄 종류 `CENTER`)
  4. 보통 `xx` + **위 첨자 글자 모양** `yy` + 각주 + `yy` + 보통 `xx` — Menlo 40pt 실선 취소선 (번호는
     위 첨자 run 안)
  5. `xxxxx` + 각주 + `xxxxx` — Menlo 40pt **긴 점선**(`LONG_DASH`) 취소선
  6. `가나K` + 각주 + `AB` — 80pt 실선 취소선, 한글 슬롯 Apple SD·라틴 슬롯 Menlo. **쪽 나누기**로
     2쪽에서 시작한다 — 1쪽 끝에 두면 80pt·줄 간격 160% 문단 프레임의 아래 여분(줄 간격 몫)이 각주
     영역까지 내려와 각주 겹침 가드(`HwpKitTests/FixtureFootnoteOverlapTests`)에 걸린다 — 가드가 그 여분까지
     본문으로 재기 때문이다(#271).
  7. `AB` + 각주 + `가나` — 6번과 같은 글자 모양 (2쪽)
- 각주 6개·미주 1개. 각주 2~6과 미주의 내용(` center`·` sup`·` dash`·` slot1`·` slot2`·` endnote`)은
  9pt 장식 없음이다. 구역 각주 모양의 번호와 각주마다의 자동 번호가 위 첨자(`supscript="1"`)이고, 미주
  번호는 위 첨자가 아니다.
- `HWPTAG_COMPATIBLE_DOCUMENT` 대상 프로그램 2
- PreviewText/PreviewImage stream, BinData storage 없음

## 한글.app 실측 (같은 세션 PDF 내보내기, 쪽 위에서부터 pt)

| 쪽 | 문단 | 표본 | 베이스라인 | 선 중심 |
|---|---|---|---:|---|
| 1 | 1 | Menlo 20pt 실선 취소선 + 각주 | 121.32 | 본문·번호·번호 뒤 116.28 |
| 1 | 2 | Menlo 40pt 실선 취소선 + 미주 | 191.88 | 본문·번호·번호 뒤 181.68 |
| 1 | 3 | Menlo 20pt 글자 가운데 밑줄 + 각주 | 266.64 | 본문·번호·번호 뒤 261.60 (자홍) |
| 1 | 4 | Menlo 40pt 보통 + 위 첨자 안 각주 | 337.20 | 보통 327.00, 위 첨자·번호 312.48 |
| 1 | 5 | Menlo 40pt 긴 점선 취소선 + 각주 | 434.16 | 본문·번호·번호 뒤 423.96 |
| 1 | 각주 1 내용 | Menlo 20pt 실선 취소선, 위 첨자 번호 | 678.00 | 번호·내용 672.84 |
| 2 | 6 | 80pt `가나K` + 각주 + `AB` (쪽 나누기) | 187.56 | `가나K` 167.64, 번호·`AB` 167.28 |
| 2 | 7 | 80pt `AB` + 각주 + `가나` | 387.12 | `AB`·번호 366.84, `가나` 367.32 |

(선 두께는 20pt 0.84·40pt 1.56·80pt 3.12pt다. 각주 구분선은 1쪽 650.16, 2쪽 712.92에 있다.)
번호 글리프는 0.75배 글꼴로 0.21em 올라가 있지만(`HwpKitTests/FixtureNoteReferenceTests`), 번호에 걸린
선은 올라가지도 가늘어지지도 않는다 — 1·2·3·5번의 번호 선은 앞뒤 본문 선과 같은 높이·두께다. 위 첨자
글자 모양 안 번호(4번)는 그 위 첨자 선(312.48)에 그리고, 각주 내용 첫머리의 위 첨자 번호도 내용 글자의
선과 같은 자리다. 긴 점선(5번)은 무늬가 번호 시작과 번호 뒤 글자 시작에서 다시 시작한다 — 한글은
번호를 앞뒤 글자와 따로 된 글자 모양 run으로 그린다. 그래서 MS 워드 호환 문서의 취소선 높이(run 글꼴
상자 `ascent`의 0.273배, #187)도 run마다 따로 잰다: 번호는 자기 글꼴(Menlo)로, 번호 뒤 글자는 자기 첫
글리프의 글꼴로 — 6번은 `가나K`(Apple SD) 167.64와 번호·`AB`(Menlo) 167.28이, 7번은 `AB`·번호(Menlo)
366.84와 `가나`(Apple SD) 367.32가 갈린다.

## 재생성 절차

1. `HwpxFixtures/footnote-endnote/document.hwpx`를 풀어 `header.xml`의
   `hh:compatibleDocument@targetProgram`을 `MS_WORD`로 바꾸고, 모든 `hh:fontface`에 `Apple SD 산돌고딕
   Neo`·`Menlo`를 더한다(`fontCnt` + 2). `hh:charPr id="0"`을 복제해 위 표본의 글자 모양을 만든다 —
   `height`, `hh:fontRef`(한글 슬롯 Apple SD, 나머지 슬롯 Menlo), `hh:strikeout@shape`(`SOLID`·
   `LONG_DASH`)·`@color` 또는 `hh:underline@type="CENTER"`·`@shape`·`@color`, 4번 위 첨자는
   `</hh:charPr>` 바로 앞에 `<hh:supscript/>`. `section0.xml`은 첫 문단 앞머리에 구역 정의 run
   (`hp:secPr`·`hp:colPr`)을 두고 `hp:footNotePr`의 `hp:autoNumFormat@supscript`를 `1`로 바꾼 뒤, 위
   순서의 7문단을 `hp:linesegarray` **없이** 적는다 (한글이 새로 조판하게). 6번 문단만
   `hp:p@pageBreak="1"`이다 (생성기의 `page_break=True`). 각주·미주는 `hp:footNote`·
   `hp:endNote` › `hp:subList` › 문단 하나에 `hp:autoNum`(각주는 `supscript="1"`, 미주는 `0`) + 내용
   텍스트다. 생성기는 로컬 `probes/256/gen256fx.py`다. `mimetype`을 `ZIP_STORED` 첫 항목으로 다시
   압축한다.
2. 그 HWPX를 `open -b com.hancom.office.hwp12.mac.general`로 연다.
3. `파일 > PDF로 저장하기...`로 같은 세션의 PDF를 내보낸다 (3쪽, A4).
4. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 파일명만 입력 → 저장
   (System Events: 저장 패널 `splitter group 1`의 `pop up button 2`·`text field "별도 저장:"`·
   `button "저장"`; 같은 이름이 있으면 시트의 `button "대치"`).
5. 같은 세션에서 다시 `다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장해
   `HwpxFixtures/note-reference-strikethrough/document.hwpx`를 갱신한다.
6. 저장된 `.hwp`를 이 디렉터리의 `document.hwp`로 복사하고 `manifest.json`의 기대값을 갱신한 뒤
   `swift test --filter "FixtureManifest|HwpxFixtureManifest|HwpxHwpEquivalence|FixtureRender|FixtureDecorationLineRender"`로
   검증한다.

생성 확인 환경:

- 앱: 한컴오피스 한글 (`com.hancom.office.hwp12.mac.general`)
- 버전: `12.30.0` build `6523`
- 생성일: 2026-10-06

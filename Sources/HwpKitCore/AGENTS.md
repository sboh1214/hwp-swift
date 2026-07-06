# HwpKitCore

Platform-neutral 렌더 코어. **AppKit / UIKit / SwiftUI / CoreAnimation import 금지.** CoreGraphics / CoreText / Foundation / CoreHwp 만 허용.

## 파이프라인 (canonical)

```
CoreHwp.HwpFile
  → HwpDocumentActor.buildDocument (HwpKitNative)
     → HwpIndex             # docInfo.idMappings 인덱싱 (charShape/paraShape/…)
     → HwpImageStore        # binItemId(1-based) → BinData 바이트 조인
     → HwpPaginator (actor) # 페이지 lazy 생성
        ├─ per paragraph
        │   flushPageBeforeProcessing  # 구역 시작·쪽 나누기 (columnType bit 2) 페이지 확정
        │   applySectionDef / applyColumnDef   # 구역 지오메트리 + 단 밴드 전환
        │   applyNewNumbers   # 새 번호 지정 (nwno, 표 144) → 쪽/각주/미주 카운터 재설정
        │   HwpTextRunBuilder → NSAttributedString
        │     (extended 컨트롤 문자 → U+FFFC + controlIndex attr + run delegate:
        │      treatAsChar 개체는 개체 크기, 그 외 extended는 폭 0 예약.
        │      controlReplacements로 마커를 번호 텍스트로 치환: 본문 각주/미주
        │      참조 (ext17)는 위 첨자, 각주 문단 자동 번호 (ext18 atno)는 "1)" —
        │      번호는 paginator 카운터가 단일 소스, 컨트롤당 1 증가)
        │   HwpParagraphLayout (CTFramesetter) → 라인 + 인라인 앵커
        │     (줄 간격 종류 (표 44/46): 비율%는 글자 크기 × 값/100 강제,
        │      고정/최소는 HWPUNIT, 여백만은 lineSpacingAdjustment)
        │   placeParagraphText   # 1단: 통 배치 / 다단: 캐시 run 단 배분, 폴백 라인 채움
        │   collectFootnotes     # 각주(페이지 하단 몫) / 미주(문서·구역 끝 몫) 분리 수집
        ├─ appendControlBlocks     # 컨트롤 → 실제 레이아웃 엔진
        │   .table  → HwpTableLayout (중첩 표 재귀 depth 3,
        │             row 단위 분할 + 페이지보다 큰 row 슬라이스,
        │             pageBreakMode == .none이면 통째로 새 페이지)
        │   gso/도형 → HwpTextboxLayout / HwpShapeGeometry / 이미지 블록
        │             (treatAsChar + FFFC 앵커 → 줄 위치 인라인 배치,
        │              이미지 crop/밝기/명암/효과 스타일 전달)
        │   .header/.footer/.pageNumberPosition/.pageHide
        │           → 활성 상태/감춤 마스크로 등록 (표 141/147/145)
        └─ per page (cacheCurrentPage)
            활성 머리말/꼬리말 밴드 반복 방출 (짝/홀 우선, pageHide 0x01/0x02 억제,
              자동 쪽 번호 (atno kind 0) 밴드는 논리 쪽 번호 치환 + 캐시 제외)
            쪽 번호 방출 (표 147/148 위치·모양·장식, pageHide 0x20 억제)
            HwpFootnoteLayout.place  # 각주 하단 배치, 넘침은 다음 페이지 이월
            HwpPaintListBuilder → HwpPaintList
        └─ 문서/구역 끝: HwpFootnoteLayout.placeFlow  # 미주 (표 134 bits 8-9)
           문서 끝 미주는 새 쪽에서 시작 (한글.app 실측 2026-07-06)
  → HwpDocument { pages: [HwpPage(blocks, paintList)], imageStore }
```

라인 세그먼트 캐시 (PARA_LINE_SEG)의 `lineLocation`은 페이지 내 절대 y다.
**실제 줄 전진량 = lineHeight + lineSpacing (per-line 캐시 필드)** — 실측:
연속 세그먼트의 lineLocation 델타와 일치 (헌법주석 30,345/30,348, noori 전부;
저장 세대와 무관). `height(for:)` = `max(loc + advance) − 첫 loc` + 문단 간격.

**페이지 지오메트리** (`HwpPageGeometry`): 본문 프레임은 머리말/꼬리말
영역(표 137)을 예약한다 — 본문 상단 = 위 여백 + 머리말 여백, 하단 =
페이지 − 아래 여백 − 꼬리말 여백 (PrvImage·헌법주석 캐시 실측). `HwpPage.margins`
는 이 본문 콘텐츠 인셋이다 (용지 여백 아님).

**절대 캐시 모드** (`detectAbsoluteCacheMode`: 첫 loc > 0인 캐시 문단이 다수):
1단 문단을 캐시가 준 y에 그대로 배치하고, 세그먼트 loc이 줄어드는 지점
(`cacheRuns`)을 한글의 페이지 절단점으로 사용한다. 여러 run에 걸친 문단은
run마다 페이지를 확정하고 CT 라인을 비례 배분해 이어 그린다. 마지막 줄의
'줄 간격' 몫이 본문 하단을 넘으면 블록 높이에서 잘라 꼬리말 밴드와 겹치지
않게 한다 (ink는 한글도 경계 안 — noori 실측). 이 모드로 헌법주석 본문
페이지 경계가 한/글 (인쇄본 캐시)과 일치한다. 전체 페이지 수는 1,031로
한글 인쇄본 (1,030) 대비 +1 — 표 분할 주변 각주 예약 근사 1건 (아래 한계).
빈 페이지에도 안 들어가는 흐름 문단은 1단에서도 라인 단위로 분할되고, 캐시
높이가 페이지를 넘는 1줄 (개체 앵커 지배) 문단은 CT 측정 높이로 폴백한다.

**캐시 높이 우선**: 각주 스택 (`HwpFootnoteLayout.measure`/예약)과 표 셀
문단 (`HwpTableLayout.placedCell`)의 높이는 유효한 라인 캐시가 있으면
`HwpParagraphLayout.cachedParagraphHeight` (한글이 계산한 줄 전진량 합)를
CT 측정보다 우선한다 — 폰트 대체로 줄 수가 부풀어 배치가 밀리는 것을 막는다.
같은 각주 컨트롤의 이어지는 문단은 간격 없이 붙는다 (캐시 loc 연속 실측).
셀 문단 전부가 캐시로 측정된 셀은 저작된 셀 높이 (표 80)를 그대로 신뢰한다.

**셀 안 그림**: 셀 문단의 그림 컨트롤은 `HwpCellImage` (표-로컬 rect)로
셀 콘텐츠에 배치되고 페이지 흐름을 소비하지 않는다 (한글.app 실측: noori
3쪽 — 흐름 방출이면 큰 그림이 페이지를 밀어낸다). row 분할 시 함께 이동.

다단은 "단 밴드" 모델이다: 단 정의 (`cold`)가 나오면 진행 중 밴드를 닫고
마지막 줄의 줄 간격만큼 띄운 뒤 (`bandTrailingLineSpacing` — Column PrvImage
실측) 그 아래에서 `HwpPageGeometry.columnFrames`로 새 밴드를 연다.
밴드가 비어 있고 라인 캐시가 단별 run (loc 리셋 = 단 경계)을 주면
`placeCachedColumnRuns`가 한글의 단별 텍스트 배분을 그대로 재현한다 —
비등폭 단은 라인 수가 아니라 textStartingIndex 글자 위치 비례 (CT 라인
스냅)로 나뉜다. 캐시가 없으면 라인 단위로 단을 채우고, 본문 텍스트가 첫
단에만 있으면 밴드를 닫을 때 라인 단위로 균형 재배치한다. 단이 차면
다음 단, 마지막 단이 차면 새 페이지 (`advanceColumn`).

## 블록 모델 gotchas

- `AnyHwpBlock.attributedString` — CT 페이로드. **immutable copy 필수** (`NSAttributedString(attributedString:)`)
- `AnyHwpBlock.payload` — 종류별 상세 결과: `.table(HwpTableFrame)` / `.textbox` / `.footnote` / `.shape(HwpShapeGeometry)` / `.image(HwpImageBlockInfo)`. payload 내부 좌표는 **블록-로컬** (footnote 의 separator 만 페이지 좌표)
- `AnyHwpBlock.source` — `HwpBlockSource(controlInstanceId/paragraphId)`: 편집 기능이 렌더 결과에서 CoreHwp 모델로 돌아가는 참조
- `AnyHwpBlock.hyperlinkURL` — block-level. `HwpPaginator.hyperlinkURL(in:)` 이 top-level 및 nested paragraph 양쪽에서 추출
- **랜덤 UUID identifier 금지.** equality/hash 는 `frame + kind + text + url + payload + source` 기반. 같은 문서 두 번 로드 시 동일 블록으로 인식되어야 함
- `HwpBlockKind`: `text` / `image` / `shape` / `table` / `textbox` / `footnote` / `placeholder`

## 앵커 규칙 (표 70)

- treatAsChar + 문단 라인에 U+FFFC 앵커 존재: 그 줄 위치에 인라인 배치.
  줄 높이는 HwpTextRunBuilder의 run delegate가 이미 예약 → 흐름 높이 추가 소비 없음.
  **표도 포함** (`appendInlineAnchoredTable` — noori 보도자료 표 실측: 캐시 줄
  높이 = 표 높이). **개체가 자기 문단 text 블록과 겹치는 것이 정상** (overlap
  검사는 text-text 쌍만)
- treatAsChar (앵커 없음) 또는 textWrap ∈ {square, tight, through, topAndBottom}: 흐름 위치에 배치 + 높이 소비. 앵커 없는 표는 이 경로 (row 분할 유지)
- textWrap ∈ {behindText, inFrontOfText}: 기준(쪽/단/문단) + 오프셋 위치에 배치, 흐름 소비 없음 — **text 블록과 겹칠 수 있음**
- 오프셋은 `Int32(bitPattern:)` 으로 읽는다 (음수 허용; `points(fromHwpUnitU:)` 금지)

## Paint list

- `HwpPaintCommand` = `@unchecked Sendable` enum. CF/NS 참조 타입을 담기 때문에 자동 Sendable 불가
- 케이스: `fillRect` / `strokeRect` / `drawText` / `drawPath` / `drawImage` / `drawImageReference(binItemId:rect:)` / `drawPlaceholder` / `hyperlink`
- `drawImageReference` 는 비트맵을 운반하지 않는다 — HwpKitNative 의 `HwpPageImageProvider` 가 `HwpImageStore` + `HwpImageCache` + `HwpImageAdapter` 로 지연 디코딩
- **`HwpPage.==` / `hash` 는 `paintList.commands.count` 만 비교** (structural fingerprint). 렌더 결과 비교용으로 쓰지 말 것

## 컨벤션

- **HWPUNIT canonical**: 변환은 `Utils/HwpUnits.swift` 에서만 (1 pt = 100 HWPUNIT). `pt` / `px` / `HWPUNIT` 혼용 금지
- **번들 폰트 금지**. `HwpFontResolver.resolve` 는 매칭 결과를 (faceName, script, size) 키로 캐시.
  후보 조회는 `HwpFontMap.candidates(forFaceName:)` — 원문 이름 → 정규화 이름
  (`-`/`#` 접두 제거 + 공백 제거) 순서. 명조 계열은 AppleMyungjo, 고딕 계열은
  Apple SD Gothic Neo 를 최종 후보로 유지할 것 (시스템 기본 설치 폰트)
- borderFill 참조는 **1-based (0 = 없음)**: `resolvedBorderFill` 은 id-1 을 먼저, 원래 id 를 다음에 시도
- Sendable actor: `HwpPaginator`, `HwpImageCache` (HwpKitNative)
- `HwpFontResolver.testDeterministic` — 스냅샷 테스트용 결정론적 resolver

## 새 블록 종류 추가

1. `Model/HwpBlock.swift` 의 `HwpBlockKind` + `Model/HwpBlockPayload.swift` 에 payload case 추가
2. `Layout/HwpPaginator.swift`: `childParagraphs(of:)` (unsupported walk) 와 `appendControlBlocks(from:depth:)` (렌더) 양쪽에 추가
3. `Paint/HwpPaintListBuilder.swift` 의 `paintCommands(for:)` 에 payload 렌더 추가
4. `Layout/HwpHitTester.swift` 의 `hit(page:point:)` 에 케이스 추가

## 안티 패턴 / 남은 한계

- `HwpPage` 렌더 결과가 다른지 `==` 로 확인 — 안 됨 (count 만 비교). blocks 배열이나 paintList.commands 를 직접 순회할 것
- 수식 (`eqed`) 은 EQEDIT 스크립트 렌더 없이 placeholder + textbox 폴백 텍스트
- 다단 세부: 캐시 run이 없는 문단의 균형 재배치·조각 높이는 라인 수 기준
  근사이고, 비균등 단으로 이월된 텍스트 조각은 draw 시 그 단 폭으로 다시
  줄바꿈된다 (블록 프레임은 단 경계 안, 시각적 줄 수는 달라질 수 있음)
- 양쪽 정렬은 draw 시 한글처럼 남는 폭을 공백에만 배분해 재조판한다
  (HwpKitNative `HwpWordJustification` — 공백 없는 줄/마지막 줄은 CT 기본).
  측정 (HwpParagraphLayout)은 CT justified 그대로 — 줄바꿈은 동일하다
- 절대 캐시 모드에서 각주 스택 높이가 한글보다 크면 (캐시 없는 각주의 CT
  측정) 본문 마지막 블록과 겹칠 수 있다 — 본문 절단점이 한글 캐시로 고정되어
  각주 예약이 본문을 밀어내지 못한다. 강제 이월은 한글에 없는 각주 전용
  페이지를 연쇄로 만들어 두지 않는다 (헌법주석 실측 1,031 → 1,054)
- 헌법주석 전체 페이지 수 1,031 (한글.app 실측 1,030 대비 +1 — 2026-07-06
  사용자 확인): 본문·각주·표 셀 높이를 캐시 기반으로 정합한 뒤에도 페이지보다
  큰 표의 분할 경계에서 각주 예약 근사 1건이 남는다 (p484 부근 — manifest
  pageCount는 렌더 값 잠금 + 출처에 실측 명시). 각주 영역을 본문 캐시 하단에
  강제로 맞추면 (minimumAreaTop) 각주 전용 페이지가 연쇄해 1,053쪽 — 두지 않음
- 셀 안 글상자/도형 (그림 제외)은 여전히 페이지 흐름 블록으로 방출된다
  (셀 위치가 아닌 흐름 위치 — 그림처럼 셀 콘텐츠로 옮기는 것은 후속 과제)
- 페이지보다 큰 표 row 슬라이스는 문단을 라인 단위로 나눠 이월하지만 (절단선은
  라인 경계로 정렬), 라인 캐시 없는 문단·조각 경계의 중첩 표는 위 조각에 통째로 남는다
- treatAsChar 줄 중간 앵커는 분할되지 않은 문단 블록에서만 동작한다
  (다단에서 라인 분할된 문단의 개체는 흐름 위치 폴백)
- 그림 효과 중 PATTERN8x8 (효과 4)은 미지원 — 원본으로 렌더
- 머리말/꼬리말 밴드 텍스트가 밴드 높이를 넘으면 본문과 겹칠 수 있다 (클립 없음)
- 각주의 표 134 bits 8-9 (한 페이지 안 다단 배열 방식) 미적용 — 항상 전체 폭 하단
- 표 셀/글상자 안 본문 문단의 각주 참조 (ext17) 위 첨자 번호는 미표시
  (각주 텍스트와 번호 자체는 정상 — HwpTableLayout 셀 조판이 마커 치환을
  받지 않는다). 표 134 번호 모양 0x80 (문자 반복)/0x81 (사용자 지정)과 쪽 번호
  userSymbol은 아라비아 폴백
- 단 나누기 (문단 헤더 columnType bit 3)와 홀/짝수 조정 (pageCT, 표 146) 미구현
  (쪽 나누기 bit 2는 구현). 각주 numberingMode == 2 (쪽마다 새로)에서 문단이
  페이지 경계 재시도로 밀리면 본문 위 첨자 번호가 재계산 전 값일 수 있다
- 쪽 번호 위치 (표 148)의 상/하 밴드 프레임이 없으면 (여백 0) 콘텐츠 경계에
  근사 배치한다. 감추기 (표 145)의 바탕쪽/테두리/배경 비트는 해당 렌더가 없어
  무시된다
- 단 종류 (일반/배분/평행)와 맞쪽 방향은 미세분화 — 밴드가 닫힐 때 항상 배분,
  방향은 왼쪽/오른쪽만; 다단에서 페이지에 걸쳐 분할된 문단의 각주는 마지막
  조각의 페이지에 귀속된다
- `HwpPaginator`는 재진입 actor다 (base부터): `page(at:)`를 병렬로 직접 부르면
  같은 문단이 중복 배치될 수 있다 — `HwpDocumentActor.buildDocument`처럼
  순차 호출을 유지할 것

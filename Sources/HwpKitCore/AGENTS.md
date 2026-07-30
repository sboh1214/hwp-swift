# HwpKitCore

Platform-neutral 렌더 코어. **AppKit / UIKit / SwiftUI / CoreAnimation import 금지.** CoreGraphics / CoreText / Foundation / CoreHwp 만 허용.

## 파이프라인 (canonical)

```
CoreHwp.HwpFile
  → HwpDocumentActor.buildDocument (HwpKitNative)
     → HwpIndex             # docInfo.idMappings 인덱싱 (charShape/paraShape/…)
     → HwpImageStore        # binItemId(1-based) → BinData 바이트 조인
     → HwpPaginator (actor) # 페이지 lazy 생성 + 문서 단위 HwpTextAttributeCache 소유
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

### Paginator/ 서브컴포넌트

`HwpPaginator`는 문단 루프·페이지 확정·블록 방출만 남기고 계산·상태 뭉치를
`Layout/Paginator/`의 컴포넌트 5개에 위임한다 — 전부 actor가 소유하는
내부 struct/enum (별도 actor 없음), 기존 호출부는 위임 계산 프로퍼티로 유지:

- `HwpPageChromeBuilder` — 머리말/꼬리말/쪽 번호 크롬 블록. 활성 컨트롤·감춤 마스크 상태 소유
- `HwpFootnoteCoordinator` — 각주/미주 수집·측정·예약. 카운터·pending·예약 높이·측정 캐시 소유
- `HwpTableSplitter` — 표 페이지 분할 플랜 (row 세그먼트·절단 기하). 상태 없는 순수 enum
- `HwpAbsoluteCachePlacer` — 절대 라인 캐시 배치 산식 + 모드·마지막 loc·stale 보정 상태
- `HwpColumnBandController` — 다단 밴드 상태 (단 정의/프레임/index/사용량/균형 재배치 입력),
  밴드 리셋 단일화 (`open`)와 균형 재배치 플랜 산출 (`rebalancePlan` → paginator 적용)

공유 흐름 상태 (`contentHeightUsed`·`paragraphAnchorTop`)와 `currentBlocks`
재작성 적용은 paginator에 남는다.

라인 세그먼트 캐시 (PARA_LINE_SEG)의 `lineLocation`은 페이지 내 절대 y다.
**실제 줄 전진량 = lineHeight + lineSpacing (per-line 캐시 필드)** — 실측:
연속 세그먼트의 lineLocation 델타와 일치 (헌법주석 30,345/30,348, noori 전부;
저장 세대와 무관). `height(for:)` = `max(loc + advance) − 첫 loc` + 문단 간격.

**페이지 지오메트리** (`HwpPageGeometry`): 본문 프레임은 머리말/꼬리말
영역(표 137)을 예약한다 — 본문 상단 = 위 여백 + 머리말 여백, 하단 =
페이지 − 아래 여백 − 꼬리말 여백 (PrvImage·헌법주석 캐시 실측). `HwpPage.margins`
는 이 본문 콘텐츠 인셋이다 (용지 여백 아님). 용지 방향(표 13 bit 0)은 여백·단
계산 **전에** `orientedPageSize`가 반영하되, 넓게 선언 + 저장 치수가 세로일
때만 축을 바꾼다 — 저장본이 이미 회전을 반영했는지와 무관하게 같은 결과를
내는 멱등 정규화다 (가로 픽스처가 아직 없어 무조건 교환은 이중 회전 위험).
구역 정의(표 132)의 머리말/꼬리말/쪽 번호 감추기는 **구역 첫 쪽에서만** 표 145
마스크와 합쳐 소비된다.

**stale 캐시 보정**: 캐시 줄 높이 (h)보다 큰 글자 크기가 선언된 문단은
캐시가 저장 당시와 안 맞는 것 — 한글.app도 열 때 재조판한다 (CharShape 실측:
상대크기 170 줄). 절대 캐시 모드에서 그 문단만 CT 높이 슬롯으로 넓히고
이후 문단을 페이지-로컬 오프셋으로 민다 (`cacheIsStale`). 신선한 캐시
(h ≥ 글자 크기)에서는 절대 발동하지 않는다 — 헌법주석 페이지 절단 유지.

**절대 캐시 모드** (`detectAbsoluteCacheMode`: 첫 loc > 0인 캐시 문단이 다수):
1단 문단을 캐시가 준 y에 그대로 배치하고, 세그먼트 loc이 줄어드는 지점
(`cacheRuns`)을 한글의 페이지 절단점으로 사용한다. 여러 run에 걸친 문단은
run마다 페이지를 확정하고 CT 라인을 비례 배분해 이어 그린다. 마지막 줄의
'줄 간격' 몫이 본문 하단을 넘으면 블록 높이에서 잘라 꼬리말 밴드와 겹치지
않게 한다 (ink는 한글도 경계 안 — noori 실측). 이 모드로 헌법주석 본문
페이지 경계가 한/글 (인쇄본 캐시)과 일치하고, 전체 페이지 수도 1,030으로
한글.app 실측과 같다 (표 셀 각주의 행 페이지 귀속 — 아래 각주 항목).
빈 페이지에도 안 들어가는 흐름 문단은 1단에서도 라인 단위로 분할되고, 캐시
높이가 페이지를 넘는 1줄 (개체 앵커 지배) 문단은 CT 측정 높이로 폴백한다.

**캐시 높이 우선**: 각주 스택 (`HwpFootnoteLayout.measure`/예약)과 표 셀
문단 (`HwpTableLayout.placedCell`)의 높이는 유효한 라인 캐시가 있으면
`HwpParagraphLayout.cachedParagraphHeight` (한글이 계산한 줄 전진량 합)를
CT 측정보다 우선한다 — 폰트 대체로 줄 수가 부풀어 배치가 밀리는 것을 막는다.
같은 각주 컨트롤의 이어지는 문단은 간격 없이 붙는다 (캐시 loc 연속 실측).
셀 문단 전부가 캐시로 측정된 셀은 저작된 셀 높이 (표 80)를 그대로 신뢰하되,
**문단 기준으로 떠 있는 개체 높이를 하한으로 얹는다** — 그 개체는 줄 상자에
없어 캐시에도 저작 높이에도 잡히지 않는다 (#91, 아래 "한계·미지원" 참조).

**셀 안 개체**: 셀 문단의 그림·도형·글상자 컨트롤은 셀 콘텐츠 (표-로컬 rect)로
배치되고 페이지 흐름을 소비하지 않는다 (한글.app 실측: noori 3쪽 — 흐름
방출이면 큰 그림이 페이지를 밀어낸다). row 분할 시 함께 이동.

다단은 "단 밴드" 모델이다: 단 정의 (`cold`)가 나오면 진행 중 밴드를 닫고
마지막 줄의 줄 간격만큼 띄운 뒤 (`bandTrailingLineSpacing` — Column PrvImage
실측) 그 아래에서 `HwpPageGeometry.columnFrames`로 새 밴드를 연다.
밴드를 닫을 자리가 (trailing gap을 더한 실제 시작점 기준) 한 줄도 안 남으면
새 페이지에서 연다 — gap을 빼고 판정하면 퇴화 밴드가 열려 본문이 하단
여백/각주 영역을 침범한다.

**문단 위 간격(beforeGap) 회계**: 조각들은 독립 CT 프레임이라 gap이 렌더되지
않으므로 첫 조각 앞에서 커서로 소비한다. 단을 넘길 때 규칙 세 가지 —
(1) 통째 이동이면 새 단 top에 gap을 **재적용**하고 `paragraphAnchorTop`도 함께
내린다 (`.paragraph` 기준 개체가 stale anchor로 뜨는 것 방지), (2) 이동 전
`markBandUsage`가 렌더되지 않을 gap을 밴드 하단으로 기록하지 않게 **차감**한다,
(3) 빈 단인지 판정은 gap을 더하기 **전** 커서로 한다 — gap 때문에 "점유된" 것으로
보이면 초과 문단이 빈 단을 건너뛴다. 단 이동이 페이지를 넘기면 각주 예약이
바뀌므로 usable 높이는 이동 후 다시 계산한다.

밴드가 비어 있고 라인 캐시가 단별 run (loc 리셋 = 단 경계)을 주면
`placeCachedColumnRuns`가 한글의 단별 텍스트 배분을 그대로 재현한다 —
비등폭 단은 라인 수가 아니라 textStartingIndex 글자 위치 비례 (CT 라인
스냅)로 나뉜다. 캐시가 없으면 라인 단위로 단을 채우고, 본문 텍스트가 첫
단에만 있으면 밴드를 닫을 때 라인 단위로 균형 재배치한다. 단이 차면
다음 단, 마지막 단이 차면 새 페이지 (`advanceColumn`).

## 블록 모델 gotchas

- `AnyHwpBlock.attributedString` — CT 페이로드. **immutable copy 필수** (`NSAttributedString(attributedString:)`)
- `AnyHwpBlock.payload` — 종류별 상세 결과: `.table(HwpTableFrame)` / `.textbox` / `.footnote` / `.shape(HwpShapeGeometry)` / `.image(HwpImageBlockInfo)`. payload 내부 좌표는 **블록-로컬** (footnote 의 separator 만 페이지 좌표). 개체를 담는 컨테이너 payload는 셋이고 필드가 대칭이다 — `HwpTableCellFrame`(images/shapes/textboxes/nestedTables), `HwpTextboxFrame`(images/shapes), `HwpFootnoteBlock`(images/shapes/textboxes/nestedTables, #94)
- `AnyHwpBlock.source` — `HwpBlockSource(controlInstanceId/paragraphId)`: 편집 기능이 렌더 결과에서 CoreHwp 모델로 돌아가는 참조
- `AnyHwpBlock.hyperlinkURL` — block-level. `HwpPaginator.hyperlinkURL(in:)` 이 top-level 및 nested paragraph 양쪽에서 추출
- 하이퍼링크 방출은 **스팬 우선**이다: `%hlk` 필드 스팬이 있으면 글리프 rect로만 방출하고, 스팬이 없는 컨테이너(표/글상자/각주) 문단만 문단 rect 폴백으로 담는다. 모델의 `hyperlinkURL`은 스팬 유무와 무관하게 채워지므로 폴백 측에서 `HwpDrawnTextLayout.hyperlinkRegions`로 게이트해야 앞뒤 평문이 링크로 표시되지 않는다 (hit tester의 `spanAwareHyperlinkURL`과 같은 규약). 컨테이너 **안쪽** 컨테이너까지 내려간다 — 각주 안 글상자·표 문단도 대상이라 방출은 `HwpPaintListBuilder.footnoteParagraphGroups` + `emitTable`이, 히트는 `HwpHitTester`의 `.footnote` 케이스가 **같은 깊이**를 걸어야 한다 (#94). 한쪽만 내려가면 밑줄은 그려지는데 탭이 안 먹거나 그 반대가 된다. 깊이만이 아니라 **영역**도 같아야 한다 — 각주 안 표는 블록 폭을 넘어 그려지는데 (한글도 안 자른다) `hit(page:point:)`의 블록 기각이 `block.frame`만 보면 그 띠의 링크가 안 눌린다. `HwpHitTester.hitEligibleFrame`이 각주 개체 rect까지 합집합으로 넓혀 페인트가 그리는 영역과 맞춘다 (R39 #3). 그 합집합과 순서는 **손으로 짜지 말고 walker에서 받는다** (R41): 자격 영역은 `walkFootnote` 방문 rect를 그대로 union하고 (최상위 rect만 모으면 각주 안 표의 셀·글상자 안 문단이 자기 컨테이너를 넘을 때 그 띠가 빠진다), 탐색은 **페인트 역순** — 안쪽 표 → 글 앞으로 개체 → 문단 텍스트 → 글 뒤로 개체 순이고 개체 정렬은 `footnoteTextboxesInPaintOrder`가 준다. 순서를 저장 순서로 두면 `.inFrontOfText` 글상자가 덮은 링크가 열린다. 컨테이너 rect로 미리 거르는 `where rect.contains` 게이트도 두지 않는다 — 포함 판정은 자손 rect를 아는 안쪽 함수 몫이다. **각주는 블록 전체 스팬 스캔(`walkText`)을 타지 않고** 그 층 인식 조회에 통째로 위임한다 (R42 #1) — `walkText`는 페인트 정순이라 덮인 문단 스팬을 먼저 잡고, 스팬 경로가 주 경로라 그대로 두면 역순 규약이 사실상 무효가 된다 (층 안에서도 문단마다 `spanAwareHyperlinkURL`이 스팬 우선을 지키므로 규칙은 잃지 않는다). 링크 없는 전경 층은 **불투명할 때만** 아래 탐색을 멈춘다 (`ContentLayer.occludes`, R42 #2) — 보이는 개체를 눌렀는데 숨은 링크가 열리면 안 되지만, 오버레이는 겹치는 것이 설계라 속 빈 장식 도형까지 막으면 그 아래 링크가 통째로 죽는다. **불투명 판정은 반드시 페인터를 보고 정한다** (R43): 글상자는 `fillColor`가 없어도 `textboxCommands`가 `.hwpWhite`로 칠하므로 **항상** 불투명하고("채우기 없음 = 투명"이 아니다), 도형은 `shapeCommands`가 `geometry.path`만 칠하므로 **경로 안쪽만** 가리며(바운딩 rect로 보면 타원 모서리의 링크가 죽는다), 표 셀은 `fillColor`가 있을 때 가린다. 그림만 알파를 알 수 없어 채워진 것으로 본다 — 그 한 가지가 한글.app 실측으로 확정할 몫이다. **컨테이너 rect로 미리 거르는 게이트는 어디에도 두지 않는다** — 중첩 표 rect(R41 #2)·셀 프레임(R44 #2)·글상자 rect(R44 #3) 셋 다, 자손이 자기 컨테이너를 넘어 그려질 수 있어 자격 영역은 인정하는데 조회만 막히기 때문이다. rect는 **가림 판정에만** 쓰고, 재귀 결과(`.occluded` 포함)는 **버리지 말고 그대로 전파**한다. 히트의 컨테이너 순회는 `containerHit` **하나**가 각주·표 셀·글상자에 재귀로 쓰인다 — 겹마다 따로 구현하면 다음 겹에서 또 갈린다(R39~R43이 전부 그 사례였다). 그래서 셀 글상자 전용 우회로(R31 #1)도 없앴다: 남겨 두면 가림으로 nil이 된 지점에서 덮인 링크가 되살아난다
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

- `HwpPaintCommand` = `@unchecked Sendable` enum. CF/NS 참조 타입을 담기 때문에 자동 Sendable 불가. enum case는 가로챌 init이 없어 **소유권 경계에서 동결**한다 — `HwpLaidOutParagraph.init`이 `NSAttributedString`을, `HwpShapeGeometry.init`이 `CGPath`를 복사본으로 저장한다 (mutable 서브클래스를 그대로 retain하면 Hashable 불변성·actor 경계 안전성이 깨진다). 새 참조 타입 payload를 추가하면 그 생산 지점에서 같은 복사를 해야 한다. 소유권 경계를 거치지 않고 **painter가 `.drawText`를 직접 만드는 경로도 마찬가지** — `HwpMemoPanelPainter`는 헤더를 `NSMutableAttributedString`으로 조립한 뒤 `NSAttributedString(attributedString:)`로 동결해 싣는다. 이제 actor 안전성 말고 **소비자**도 생겼다: HwpKitNative의 줄 배치 캐시가 문자열 신원 (`===`)으로 조판 결과를 재사용하므로 "신원이 같으면 내용도 같다"가 전 생산 경로에서 성립해야 한다 (깨지면 조용한 오조판)
- 케이스: `fillRect` / `strokeRect` / `drawText` / `drawPath` / `drawImage` / `drawImageReference(binItemId:rect:)` / `drawPlaceholder` / `hyperlink`
- `drawImageReference` 는 비트맵을 운반하지 않는다 — HwpKitNative 의 `HwpPageImageProvider` 가 `HwpImageStore` + `HwpImageCache` + `HwpImageAdapter` 로 지연 디코딩
- **`HwpPage.==` / `hash` 는 `paintList.commands.count` 만 비교** (structural fingerprint). 렌더 결과 비교용으로 쓰지 말 것
- **메모 (댓글) 풍선**: `HwpPage.memoPanel` (`HwpMemoPanel` — 폭 + 패널 로컬
  paintList)에 분리 저장 — 종이 밖 오른쪽 패널이라 페이지 paintList/PrvImage
  정합에 영향 없음. 내용은 CoreHwp `HwpParagraph.memoParagraphArray` (MEMO_LIST
  뒤 문단 자식), 작성자/시각은 memo 필드 `HwpMemoFieldParameter` (fields[2]/[3] =
  FILETIME low/high — `HwpPaginator.memoDateText`). 풍선 그리기는
  `HwpMemoPanelPainter` (연녹색 풍선 + 작성자·시각·"댓글" 헤더 + 본문 + 점선
  연결선 — 한글.app 편집 뷰 실측). 앵커 텍스트는 run builder가
  `memoAnchorRanges` (필드 시작 extended ~ 필드 끝 inline 4)로 연녹색 음영
  (`HwpAttributedStringKey.shadeColor`). 네이티브 뷰가 페이지 오른쪽에 투명
  `HwpPageLayer`로 그린다 (`memoPanelLayers`)

## 컨벤션

- **HWPUNIT canonical**: 변환은 `Utils/HwpUnits.swift` 에서만 (1 pt = 100 HWPUNIT). `pt` / `px` / `HWPUNIT` 혼용 금지
- **번들 폰트 금지** (라이브러리에 폰트 동봉 금지 — `.gitignore`와 pre-commit
  훅이 폰트 확장자를 차단한다). 이 기기에 한컴오피스가 설치되어 있으면 그 앱
  번들 TTF (`Hnc/Shared/TTF/`)를 `HwpInstalledHancomFonts`가 파일 descriptor로
  인덱싱해 쓸 수 있지만 **기본은 off**다 — 그 디렉터리엔 한컴이 자사 오피스
  안에서 쓰라고 라이선스받은 타 파운드리 폰트가 섞여 있다 (2026-07-27 실측:
  187개 / OS/2 achVendID 18종, Monotype `arial`·`malgun`·`Calibri` 포함).
  `HWP_HANCOM_FONTS=1` 또는 `HwpFontResolver(usesInstalledHancomFonts: true)`로
  opt-in하면 HY헤드라인M 등이 한글.app과 같은 글리프로 렌더된다. macOS 경로만
  보므로 iOS 기기에서는 인덱스가 항상 비고 이 스위치도 무효다.
  **스위트를 폰트 모드로 가르지 않는다** (`skipUnlessOptedIn`에 폰트 인자 없음)
  — 한쪽 모드에서 영영 실행되지 않는 스위트가 생긴다. 모드 축을 감당하는 방법은
  스위트마다 다르다: 렌더 해시는 모드별 기준선 파일 (opt-in `<id>.json` / 기본
  `<id>-nohancom.json`)로 양쪽을 각각 잠그고, fidelity는 양 모드에서 성립하는
  임계를 쓰며, **커밋된 기준선을 쓰는 계열** (블록 스냅샷·렌더 골든·페이지 수)은
  `testDeterministic`으로 로드해 모드 축 자체를 없앤다 (#69).
  전역 등록은 하지 않는다 (결정론 테스트 조회 오염 방지; `testDeterministic`은
  이 인덱스 자체를 끔). 이름 매칭은 name table 기본 + 로컬라이즈 이름 (한글) 둘 다.
  `HwpFontResolver.resolve` 는 매칭 결과를 (faceName, alternatives, script, size)
  키로 캐시. 해석 순서: 원문 이름 → `HwpFontMap.candidates(forFaceName:)` 폴백
  (원문 이름 → 정규화 이름 (`-`/`#` 접두 제거 + 공백 제거) 순) → 문서가 선언한
  대체/기반 글꼴 (아래 항목) → script 폴백. 각 후보는 시스템 → (opt-in 일 때만)
  한컴 번들 순으로 조회하되, 시스템 조회도 `usesSystemFontLookup` 게이트를
  지나므로 결정론 resolver에서는 이 단계가 통째로 빠진다 (아래 항목).
  명조 계열은 AppleMyungjo, 고딕 계열은
  Apple SD Gothic Neo 를 최종 후보로 유지할 것 (시스템 기본 설치 폰트)
- **한컴 인덱스를 resolver 밖에서 직접 조회 금지** — `HwpInstalledHancomFonts`
  를 보는 코드는 반드시 `HwpFontResolver.usesInstalledHancomFonts` 를 함께
  확인해야 한다 (`serifLatinFallback` 이 인자로 받는 이유). 무조건 조회하면
  ① opt-in 을 껐는데도 앱 번들 폰트 파일을 열거하고 ② 결과가 한컴오피스 설치
  여부에 좌우돼 **배포 기본 경로의 렌더가 기기 의존**이 된다
- **문서가 적어 둔 대체 글꼴을 후보로 쓴다** — `HwpFaceName` 의
  `alternativeFaceName` (대체 글꼴)·`defaultFaceName` (기반 글꼴)을
  `resolve(faceName:alternatives:script:size:)` 로 넘긴다. 큐레이션한 `fontMap`
  을 **다 쓴 뒤** script 폴백 직전에 시도한다 — 맵에 있는 face 는 검증된 해석을
  그대로 두고 (렌더 기준선 보존), 맵에 없는 face 만 구제한다. 맵은 ~50개인데
  실제 문서의 face 는 그보다 훨씬 많다. 각 대체명은 그 자체로 다시 map 을
  거친다 (대체명도 HWP face 이름이라 시스템 폰트명이 아니다 — "Myeongjo" 의
  대체는 "명조"). 캐시 키에 대체명이 들어가야 문서 간 오염이 없다
- **매핑 없는 face 는 script 폴백 (한글 슬롯 = 고딕) 으로 떨어진다** — 명조
  계열이 고딕으로 렌더되는 계열 오분류가 여기서 나온다. 로마자 표기 변형
  (`Myeongjo`, `HY Sinmyeongjo`) 과 고정폭 변형 (`굴림체`) 은 `normalize` 로도
  안 잡히니 `HwpFontMap` 에 개별 항목으로 넣을 것. 이름만 보고 계열을 단정하지
  말고 face 이름이 실제로 무엇의 별칭인지 확인한다 — `한컴바탕확장` 은 한글
  바탕이 아니라 한자용 송체이고 (문서의 `FaceName.defaultFaceName` 이
  `FZSong_Superfont` 로 못박는다), `Apple SD 산돌고딕 Neo` 는 시스템 폰트의
  한글 표시명이라 매핑이 없으면 로마자 슬롯이 Helvetica 로 대체된다
- **글자 모양 속성 캐시** (`HwpTextAttributeCache`) — `HwpTextRunBuilder.attributes`
  는 `index`·`fontResolver` 가 고정이면 `(shapeId, script)` 의 순수 함수라
  (장평·이탤릭 근사 매트릭스·라틴 세리프 폴백·장식이 전부 charShape 에서만
  나온다) 텍스트 조각마다 하던 재계산을 메모한다. 문단마다 달라지는 값
  (변경추적 표시·메모 앵커·controlIndex·run delegate·첨자 치환)은 전부 **반환
  뒤** 사전 사본에 붙으므로 키에서 구조적으로 빠져 있다. 지켜야 할 것 셋:
  ① **돌려받은 사전을 제자리에서 변형 금지** — 공유 인스턴스라 값
  (CTFont/CGColor/NSNumber)을 바꾸면 다른 호출부까지 오염된다. `var` 사본에
  키 추가·치환만 한다. `attributes` 에 가변 NSObject (NSShadow·
  NSMutableParagraphStyle 등)를 새로 넣으면 이 계약이 조용히 깨진다.
  ② **소유는 문서 단위** (`HwpPaginator` 가 하나 만들어 표/글상자/각주/크롬에
  주입) — `shapeId` 의 의미가 `HwpIndex` 마다 다르고 `usesInstalledHancomFonts`
  는 resolver 별 값이라, 전역·resolver 소유면 문서·폰트 모드가 섞인다.
  ③ 그 규약을 타입으로 강제할 수 없어 **캐시 타입과 캐시를 받는 init 은 전부
  internal** 이다. public init 은 캐시 없는 기존 시그니처를 유지한다.
  탭 스톱도 같은 캐시에 있다 (`textTabs(for:index:)` — `HwpIndex.textTabs` 는
  호출마다 `CTTextTab` 을 새로 만드는데 문단마다 측정·렌더로 불린다). 키가
  `tabDefId` **하나뿐**이라, `HwpIndex.textTabs(for:)` 가 paraShape 의 다른
  필드를 보게 되면 조용히 틀린 탭을 준다 (실측 확인: 현재는 `tabDefId` 만
  읽는다). 속성 키도 같은 성질이지만 그쪽은 타입이 막는다 — `resolvedShape` 가
  shape 와 캐시 키를 `ResolvedShape` 한 값으로 묶어 주고 `attributes(for:script:)`
  가 그 타입만 받아, 어긋난 짝을 넘길 길이 없다.
  **`index` 에 없는 id 는 캐시 키가 `nil` 로 접힌다** — 폴백 (`resolvedShape`) 이
  문단과 무관한 상수라 결과 사전이 전부 같은데, 원본 id 로 키를 잡으면 조작
  문서가 문자마다 다른 id 를 흘려 내용이 같은 항목을 문서 수명 내내 쌓는다.
  저장소별 항목 상한 (`maximumStoredEntries` 65,536)은 **축출이 아니라 삽입
  중단**이다 — 조판이 문서를 순서대로 훑으므로 FIFO 축출은 워킹셋이 상한보다
  클 때 히트율 0% 가 된다 (`HwpPageLayer` 줄 배치 캐시와 같은 이유). 미스가
  `create` 폴백이라 삽입을 멈춰도 결과는 같다.
  주입 경로는 ②의 넷 말고 `HwpParagraphMeasurer` · `HwpParagraphObjectCollector`
  까지다 (컨테이너 안 글상자가 자체 `HwpTextboxLayout` 을 만드는 경로) —
  **새 레이아웃 컴포넌트는 캐시를 함께 실을 것**.
  안 실어도 결과는 같고 (nil 이면 매번 재계산) 조용히 느려질 뿐이라 테스트로
  안 잡힌다. 동기화는 `NSLock` 으로 저장소 접근만 감싸고 `create` 는 lock
  밖이다 (`HwpFontResolver.FontCache` 와 같은 절충 — 경합하면 같은 키를 두 번
  만들 수 있지만 순수 함수라 결과가 같다).
  실측 (로컬 macOS, 3회 median, 캐시 무력화 A/B): paginate N=20,000 (589쪽)
  10.95 → 6.17s (**1.78x**), legacy 1,030쪽 문서 로드 26.37 → 18.53s
  (**1.42x**). 등가성은 렌더 픽셀 해시 전 픽스처 × 전 페이지 0건 (양 폰트
  모드). 회귀 가드는 `HwpTextRunBuilderTests` 의 캐시 7종 (캐시/무캐시 문자열
  동치, 히트·미스 카운트, script 키 분리, 변경추적 마크 비오염, 탭 스톱
  재사용, 미해결 id 64개 → 항목 1개, 상한 초과 시 삽입 중단 + 결과 불변) —
  캐시를 건드리면 `hitCount`/`missCount`/`entryCount` (테스트 전용 관측점) 로
  단언할 것
- 실측 튜닝 상수는 `Tuning/HwpRenderTuning.swift` 에 근거 주석과 함께 —
  값 변경은 fidelity 전수 + 블록 스냅샷 + 실물 대조 필수 (값 핀:
  `HwpRenderTuningTests`). 차트 투영 기하 (`HwpChartPainter`)와 각주 예약
  근사 (`HwpPaginator`)는 예외로 in-place
- borderFill 참조는 **1-based (0 = 없음)**: `resolvedBorderFill` 은 id-1 을 먼저, 원래 id 를 다음에 시도
- Sendable actor: `HwpPaginator`, `HwpImageCache` (HwpKitNative)
- **`HwpFontResolver.testDeterministic`은 폰트 조회 세 축을 모두 닫는다** —
  시스템 등록 폰트 (`usesSystemFontLookup`)·한컴 번들 (`usesInstalledHancomFonts`)·
  문서 대체 글꼴 (`usesDocumentAlternatives`). 모든 face가 Menlo로 떨어져 설치
  폰트와 무관하게 같은 CTFont가 나오고, 그 덕에 **커밋된** 기준선을 쓰는 렌더
  가드 3종이 CI와 기여자 머신에서 함께 돈다 (루트 AGENTS.md "렌더 가드 3층").
  시스템 축이 가장 늦게 닫혔다 (#69) — HWP 원문 face 이름이 그 자체로 시스템
  폰트명일 수 있어 (`굴림`·`바탕`은 MS Office가, `함초롬바탕`은 한글 정식 설치가
  같은 한글 이름으로 등록한다) 나머지 두 축만 닫으면 그 폰트가 깔린 머신에서만
  실폰트로 조판된다. 조회 축을 새로 더하면 **여기서도 함께 닫고**
  `HwpFontResolverTests`에 축별 가드를 추가할 것 — 결정론 쪽만 단언하면 플래그가
  반대로 꽂혀 기본 resolver의 조회까지 꺼져도 통과하므로, 두 resolver가 같은
  이름을 다르게 본다는 것까지 단언한다 (`resolve`는 전 문서 로드의 핫패스다).
  완전한 결정론은 아니다: Menlo에 한글 글리프가 없어 한글 폴백이 OS
  캐스케이드에 맡겨진다 (macOS 버전 간 잔차 — 기준선 임계가 흡수할 몫)

## 새 블록 종류 추가

1. `Model/HwpBlock.swift` 의 `HwpBlockKind` + `Model/HwpBlockPayload.swift` 에 payload case 추가
2. `Layout/HwpPaginator.swift`: `childParagraphs(of:)` (unsupported walk) 와 `appendControlBlocks(from:depth:)` (렌더) 양쪽에 추가
3. `Paint/HwpPaintListBuilder.swift` 의 `paintCommands(for:)` 에 payload 렌더 추가
4. `Layout/HwpHitTester.swift` 의 `hit(page:point:)` 에 케이스 추가
5. **문단을 품는 payload면** `Selection/HwpBlockContentWalker.swift` 에 순회를 더하고
   3의 렌더를 그 walker로 구현한다 — walker 가 텍스트·개체 방출 **순서의 단일
   소유자**라 페인트·선택 (`HwpSelectableText`)·**히트 (4)** 가 정의상 같은
   순서를 본다. 히트는 그 **역순**이다 (위에 그려진 것이 이긴다).
   3만 채우면 그려지긴 하는데 선택·복사에서 그 텍스트가 빠지고, 순서를 양쪽에
   따로 구현하면 조용히 갈린다 (가드: `HwpSelectableTextPaintParityTests`).
   개체까지 품는 컨테이너면 `walkTable`/`walkFootnote` 와 같은 이벤트 규약을
   따르고 (글 뒤로 개체 → 문단 텍스트 → 나머지 개체 → 안쪽 표 재귀), 정렬은
   공용 `sortedObjects` (zOrder → 원본 순서) 를 쓴다

## 안티 패턴 / 남은 한계

- `HwpPage` 렌더 결과가 다른지 `==` 로 확인 — 안 됨 (count 만 비교). blocks 배열이나 paintList.commands 를 직접 순회할 것
- 수식 (`eqed`) 은 EQEDIT 스크립트를 한 줄 텍스트로 근사 (`HwpEquationLayout`
  — 기호 토큰 치환 + 관계 연산자 공백, 라틴 문자 이탤릭). 분수/근호 같은
  구조 조판은 없음 — 스크립트 원문이 노출된다
- OLE 내장 차트는 `OOXMLChartContents` XML (CoreHwp `HwpEmbeddedChart`,
  자체 CFB 리더 — OLEKit 은 miniFAT 없는 내장 CFB 를 거부) 을 파싱해
  `HwpChartPainter` 로 렌더. 기하는 한글.app mac 렌더러 실물 캡처 (2026-07-10)
  픽셀 실측 **3D 상자 모델** (`Box`): 앞 축 x=0.140W, 바닥 전면 y=0.824H,
  바닥 앞-오른쪽 x=0.670W, 깊이 벡터 (0.104W, −0.124H), 벽 높이 0.411H —
  눈금별 깊이 세그먼트 + 수평 그리드 뒷벽 + 평행사변형 바닥. 계열은 깊이
  진행률 0.8/(n−1) 간격으로 물러나고 원뿔 폭 = 그룹폭 0.374. 실물 계열색
  (#7682CF/#DA914D/#B2B2B2 — Office accent보다 연함), 미세 좌우 명암 (mac
  렌더러는 거의 평면). **한글.app mac 렌더러의 3D는 소실점 원근이 아니라
  평행 (oblique) 투영** — 실측 근거: 뒷벽 그리드가 양끝에서 y 동일 (수렴 0),
  눈금 간격 좌우 동일 (44.5px), 깊이 세그먼트 전부 평행, 원뿔 폭 전 계열
  동일 (감쇠 없음). 같은 투영 모델이므로 각도 차이 없음. pie/line 등 기타
  차트 종류는 미재현 (전부 세로 막대 취급). 자동 제목은 한컴 기본 "차트 제목" 폴백
- 다단 세부: 캐시 run이 없는 문단의 균형 재배치·조각 높이는 라인 수 기준
  근사이고, 비균등 단으로 이월된 텍스트 조각은 draw 시 그 단 폭으로 다시
  줄바꿈된다 (블록 프레임은 단 경계 안, 시각적 줄 수는 달라질 수 있음)
- 양쪽 정렬은 draw 시 한글처럼 남는 폭을 공백에만 배분해 재조판한다
  (`Text/HwpWordJustification` — 공백 없는 줄/마지막 줄은 CT 기본).
  측정 (HwpParagraphLayout)은 CT justified 그대로 — 줄바꿈은 동일하다.
  문서 정의 탭 스톱 (`HwpIndex.textTabs`)과 slight-overflow 한 줄 규칙
  (`HwpDrawnTextLayout.slightOverflowLineMetrics` 공유 술어)은 측정·렌더가
  같은 입력을 쓴다 — 탭 문단 줄바꿈·한 줄 문단 높이가 정의상 일치
  (가드: HwpParagraphLayoutTests.testTabParagraphMeasurementMatchesDrawnLayout)
- **각주/미주도 표 셀·글상자와 같은 컨테이너다** (#94). `HwpFootnoteBlock`이
  `images`/`shapes`/`textboxes`/`nestedTables`를 블록-로컬 rect로 들고,
  `HwpFootnoteLayout.measure`가 `HwpParagraphObjectCollector`로 수집한다
  (`collectsTables: true` — 셀은 `PlacedCellContent.nestedTables`가 따로
  배치하지만 각주에는 그 경로가 없다). 페인트·선택·히트는
  `HwpBlockContentWalker.walkFootnote` 한 지점이 순서를 정의한다 (글 뒤로 개체 →
  문단 텍스트 → 나머지 개체 → 각주 안 표 재귀 — `walkTable`과 같은 규약).
  개체를 **페이지 흐름으로 방출하지 않는다**: 흐름으로 내보내면 각주 영역 밖
  본문 자리에 그려지고 흐름까지 밀어낸다. 그래서 `HwpPaginator`의
  `.footnote/.endnote` 케이스는 형제 케이스와 달리
  `appendNestedControlBlocks`를 부르지 않고, 수집기가 담지 못하는 컨트롤
  (OLE·수식)은 `walkUnsupported`가 각주 문단까지 걸어 (childParagraphs) 진단으로
  보고한다.
  한글.app 실측 (2026-07-30, 헌법주석 `legacy-common-control-property`):
  인쇄 459쪽 (= 렌더 인덱스 470) 각주 38)의 9.6×10.8pt 그림은 "1970년의 씨▨의
  소리사"의 **글자 자리**에 저작 크기 그대로 놓이고 각주는 3줄 그대로다;
  인쇄 883쪽 (= 렌더 인덱스 894) 각주 29)의 4×8/22셀 408×62.52pt 표는 각주 29의
  둘째 문단으로 **각주 영역 안**에 그려지고 그 아래로 각주 30)이 이어지며,
  문단 들여쓰기 (≈17.9pt)에서 시작해 오른쪽 본문 경계를 ~12.6pt 넘어간다
  (한글은 자르지도 줄이지도 않는다 — 그래서 폭 기준을 문단 rect 폭으로 두고
  위치만 앵커에 맞춘다). 폭 클램프는 흐름 경로(`HwpPaginator`)와 **같은 술어**를
  쓴다 — `treatAsChar || consumesFlow`, 즉 비흐름 오버레이(글 뒤로·글 앞으로)는
  저작 폭을 지킨다 (R43 #1). `HwpTableLayout.layout`의 기본값이 `true`(줄인다)라
  인자를 생략하면 한글이 안 줄이는 표를 우리만 줄인다. 883쪽 표가 이 버그에 안
  걸린 것은 우연이다 — 글자처럼 취급이라 클램프 대상인데 저작 폭(408pt)이 문단
  폭보다 작아 무동작이었다. **쪽 번호 대응**: 이 픽스처는 앞 로마자 12쪽 뒤 본문이
  1로 재시작하므로 렌더 페이지 인덱스 N ↔ 한글 인쇄/상태바 쪽번호 N−12다
  (한글 찾아가기도 인쇄 번호를 쓴다) — 실측 지점을 찾을 때 이 오프셋을 잊지 말 것.
- **각주 블록 높이도 셀과 같은 규약이다** (#94): 갈리는 축은 배치 방식이 아니라
  **줄 앵커 유무**다 (R40 #1). 앵커를 얻은 글자처럼 취급 개체는 run delegate가
  줄 높이로 예약하므로 라인 캐시가 담는 몫이라 하한을 얹지 않고 (883쪽 표는 캐시
  71.32pt, 459쪽 그림은 3줄 36.96pt 안에 들어간다 — 실측 일치), **앵커를 못 얻은
  글자처럼 취급 개체**는 어떤 줄도 자리를 잡아 주지 않아 컨테이너가 직접 담는다
  (루트 "앵커 규칙"의 "treatAsChar (앵커 없음) → 높이 소비"를 컨테이너 높이로
  옮긴 것). 떠 있는 개체와 합쳐 술어는 `raisesContainerFloor`
  (= `growsContainer` ∪ `escapesLineBox`) 하나가 소유하고 표 셀·각주가 공유한다.
  앵커를 모르는 사전 판정 (`hasFloatingObject`)만 **상위집합**이다 — 좁으면 하한을
  놓치고 넓으면 재수집만 한 번 더 도므로 불일치는 그 방향으로만 안전하다. 예약
  (`HwpFootnoteCoordinator.measuredFootnoteHeight` → 본문 절단점)과 배치
  (`stackBlocks`)는 **같은 함수** `HwpFootnoteLayout.measureNote`를 부른다 —
  산식을 복제하지 않고 호출을 공유해야 앵커 판정까지 일치한다. 예약이 줄 없는
  프레임 (`HwpParagraphFrame(lines: [])`)으로 따로 재던 것이 R40 #1을 막고 있던
  걸림돌이었다 (앵커 있는 개체까지 "앵커 없음"으로 보여 예약만 부풀었다).
  개체 없는 각주는 `hasFloatingObject`로 걸러 라인 캐시 빠른 길을 유지한다.
  축이 하나 더 있다 — **시간**이다 (R44 #1): `HwpPaginator.objectSizeResolver`는
  현재 단·문단 폭을 읽는 **계산 프로퍼티**라 시점마다 값이 다르므로, 예약이 쓴
  해석기를 `HwpFootnoteLayout.Input.sizeResolver`에 실어 배치까지 들고 간다.
  배치 시점에 다시 읽으면 그 사이 단 밴드가 바뀐 문서에서 `.column`·`.paragraph`
  기준 개체가 다른 크기로 재조판된다 — 예약이 작으면 각주
  스택이 본문을 덮고, 크면 한글에 없는 페이지 절단이 생긴다. 코퍼스에는 떠 있는
  각주 개체가 0건이라 (전 픽스처 스캔: gso 1 + table 1, 둘 다 글자처럼 취급)
  이 하한은 헌법주석 페이지 수 1,030과 렌더 해시를 건드리지 않는다 —
  #94에서 바뀐 페이지는 470·894 **두 장뿐**이다.
  남은 차이 하나: 한글은 각주에서 **「글 앞으로」·「글 뒤로」에도** 영역을
  키우는데 (2026-07-30 합성 실측 — 각주 문단에 떠 있는 도형을 붙이면 구분선이
  위로 밀린다), 우리는 `growsContainer`의 오버레이 제외를 그대로 따른다.
  술어의 소유자는 `HwpParagraphObjectCollector` 한 곳이어야 하고 (표 셀·흐름
  경로가 같은 답을 써야 한다) 오버레이 제외는 #91이 셀 페이지 분할을 지키려
  둔 가드다 — 바꾸려면 표 셀과 **함께** 코퍼스 전체로 검증할 것.
  가드: `HwpFootnoteObjectLayoutTests` (합성 13종 — 종류별 수집, 캐시 높이 불변,
  떠 있는 개체/표 하한, 쪽 기준·오버레이 제외, **예약 ≡ 배치 높이**, 흐름 비방출,
  각주 안 개체 링크 히트) + `HwpFootnotePaintListTests` (페인트 명령·z순서 3종) +
  `FixtureObjectRenderTests`에 #94가 더한 3종 (헌법주석 실픽스처 470·894쪽 —
  그림/표가 각주 블록 프레임 **안**에 있고 흐름 블록으로 새지 않음) +
  `HwpSelectableTextPaintParityTests`
  (선택 단위 9개: 각주 문단 뒤에 각주 글상자·표 셀 텍스트) + 블록 스냅샷 표본
  470·894쪽 (루트 AGENTS.md "렌더 가드 3층").
- **각주 컨테이너에서 갈리기 쉬운 두 값** (R39 — #94 리뷰가 잡은 것):
  ① **문단 rect ≠ 블록 높이**. 문단 rect는 `MeasuredFootnote.textRectHeight`
  (문단 자신의 텍스트 높이)를 쓴다 — 블록 높이(떠 있는 개체 성장분 포함)를
  문단에 주면 문단-레벨 링크 폴백이 개체 아래 **빈 영역까지** 자기 URL로
  claim한다. 코퍼스에 떠 있는 각주 개체가 0건이라 두 값이 늘 같아 되돌려도
  렌더·해시가 무변화다 — `testFloatingObjectGrowsBlockButNotParagraphRect`만이
  가드다. ② **예약 캐시 키는 해석기를 통째로 든다** (`FootnoteHeightKey`).
  상대 크기 개체가 든 문단은 줄 높이가 `HwpObjectSizeResolver` 기하의 함수인데
  폭만 키에 넣으면 종이/쪽 높이·단 폭만 바뀐 재사용이 살아나 예약이 배치와
  갈린다 (배치는 캐시가 없어 늘 현재 기하로 재측정하므로 틀리는 쪽은 예약이다).
  resolver의 `Hashable`이 **합성**이라 기준 축을 더해도 키가 따라간다 —
  손으로 구현하지 말 것. 가드: `testReservationIsNotReusedAcrossResolverGeometries`.
- 절대 캐시 모드에서 각주 스택 높이가 한글보다 크면 (캐시 없는 각주의 CT
  측정) 본문 마지막 블록과 겹칠 수 있다 — 본문 절단점이 한글 캐시로 고정되어
  각주 예약이 본문을 밀어내지 못한다. 강제 이월은 한글에 없는 각주 전용
  페이지를 연쇄로 만들어 두지 않는다 (헌법주석 실측 1,031 → 1,054)
- 표 셀 각주는 소유 문단 페이지가 아니라 그 셀의 행이 실리는 페이지에
  수집·예약한다 (`collectTableCellFootnotes` — 세그먼트 행 범위 기준, 한글
  실측 헌법주석 p485). top-level `collectFootnotes`는 표 셀을 건너뛰고
  (`includeTableCells: false`), 예측 (`anticipatedFootnoteBodyHeight`)도
  동일하게 제외한다. 절대 캐시 모드에서는 각주 스택 면적 상한 (본문 절반)도
  해제 (`limitsAreaToHalfContent: false`) — 이 두 가지로 헌법주석 전체
  페이지 수가 한글.app 실측 1,030과 일치 (2026-07-10). 각주 영역을 본문 캐시
  하단에 강제로 맞추면 (minimumAreaTop) 각주 전용 페이지가 연쇄해 1,053쪽 — 두지 않음
- **셀 높이는 라인 캐시·저작 높이 위에 "떠 있는 개체" 하한을 얹는다** (#91).
  `hasCachedContent`일 때 저작된 셀 높이 (표 80)를 신뢰하는 규약은 **글자처럼
  취급되지 않는 개체에는 성립하지 않는다** — 그런 개체는 줄 상자에 들어가지
  않아 한글 라인 캐시에도, 저작 셀 높이에도 없다. noori 3쪽 붙임 표 실측:
  형상 행 셀의 저작 높이 12.82pt·캐시 줄 높이 16.00pt인데 그 안의 떠 있는
  그림이 455.40pt여서, 그 둘만 믿으면 행이 라벨 한 줄로 접히고 그림이 아래
  행들을 덮으며 표 밖으로 흘러나갔다 (표 총높이 181.6pt = 선언 627.0pt의 29%).
  `HwpTableLayout.floatingObjectHeight`가 배치 (`laidOutContents`)와 **같은
  collector·같은 문단 쌓기**로 셀-로컬 좌표에서 개체 하단을 재수집해
  `여백 + 하단 + 여백`을 하한으로 준다 — 개체 위치가 문단 rect의 아핀
  평행이동이라 셀 원점 없이도 상대 하단이 같다. 형상 행 458.22pt로 표 총높이가
  문서 선언·한글 캐시와 같은 627.01pt가 된다. 글자처럼 취급 개체에는 하한을
  얹지 않는다 — 줄 캐시가 담는 몫이고, 얹으면 캐시 신뢰 규약 (헌법주석 실측)이
  깨진다. **하한은 세로 기준이 '문단'이고 배치 방식이 흐름을 점유하는 개체만**
  얹는다 (`growsContainer` — 축 3개; 앵커를 못 얻은 글자처럼 취급 개체는
  `escapesLineBox`로 따로 더해진다, R40 #1). 쪽/종이 기준 개체의 저작 오프셋은 페이지
  상단 기준 절대 좌표(수백 pt가 정상)인데 컨테이너 안에는 쪽 기하가 없어
  `origin()`이 그 값을 문단 rect에 더하는 근사를 쓰고(R32 #3), 그 근사를 높이
  하한으로 승격시키면 개체 위치 오차가 표 총높이·페이지 분할 오차로 번진다
  (실측: 저작 10pt 셀 + 쪽 기준 오프셋 600pt 개체 → 행 700pt). 한글도 쪽에 걸린
  개체를 담으려고 셀을 키우지 않는다. 같은 꼴로 **글 뒤로·글 앞으로도 뺀다** —
  그 배치 방식은 겹치는 것이 설계라(위 "앵커 규칙") 담으려고 컨테이너를 키우면
  셀 안 워터마크·말풍선 하나가 행을 부풀린다. 술어는
  `HwpParagraphObjectCollector.consumesFlow`가 **단일 소유**하고 페이지 흐름
  경로(`HwpPaginator.consumesFlow`)가 그것을 부른다 — 갈리면 흐름에서 자리를
  안 주는 개체가 컨테이너만 키우는 모순이 된다. 여기서 빠져도 셀 콘텐츠로
  그려지는 것은 그대로다 (`paintsBehindText`) — 빠지는 것은 **높이 하한뿐**이고,
  수집에서 빼면 개체 소실 회귀다.
  `objects()`의 기록 조건과 `hasFloatingObject` 사전 판정도 **반드시 같은
  술어**를 써야 한다 — 갈리면 걸러진 셀이 하한을 못 받는다.
  noori 형상 행 개체는 '자리 차지'(`.topAndBottom`)라 이 축을 더해도 #91은
  그대로 성립한다 (실측 — 픽스처 코퍼스에 셀 안 오버레이 개체는 아직 없어
  이 축은 양 폰트 모드 렌더 해시 무변화로 도입됐다).
  가드: `HwpTableFloatingObjectLayoutTests` (셀 높이 전용 스위트 — 폭·분할을
  보는 `HwpTableLayoutTests`와 분리) 의 floating/inline/쪽 기준/오버레이 네 짝 +
  문단 쌓기 (앞 문단·문단 위 간격·중첩 표) 담김 테스트 + noori p3 골든
- 셀 안 그림·도형·글상자는 셀 콘텐츠로 배치된다 (0357d24, R29 #1). 다만 ole
  (내장 차트)를 품은 컴포넌트와 수식 컨트롤은 수집 대상이 아니라 페이지 흐름
  경로가 그린다 (`collectible`·`handledControl` — 흐름 억제 술어
  `rendersInsideContainer`와 반드시 일치해야 한다, 불일치 = 소실 또는 이중 렌더)
- **컨테이너 안 글상자의 안쪽 컨테이너는 조용히 사라진다** (R40 #2, 미해결).
  `HwpTextboxLayout`은 글상자 안 글상자·표를 수집하지 않고 (`collectsTextboxes:
  false` + `collectsTables` 미지정 — R29 #1의 재귀 차단), 최상위 글상자는 안쪽
  표를 **흐름 경로**가 대신 그린다. 그런데 각주는 흐름 방출이 없어 (위 각주 항목)
  각주 → 글상자 → 표가 페이로드에도 흐름에도 없다. 표는 **지원** 컨트롤이라
  `unsupportedDetector.classify`가 nil을 돌려 진단도 안 뜬다 — OLE·수식만 걸린다.
  #94가 만든 회귀는 아니다 (그 전엔 바깥 글상자조차 안 그려졌다).
  고치려면 `HwpTextboxFrame`에 `textboxes`/`nestedTables`를 셀·각주와 대칭으로
  더하고 walker·페인트·히트를 **함께** 배선해야 한다 (한 곳만 하면 죽은
  페이로드거나 선택↔렌더 불일치). **최상위 글상자에서는 켜면 안 된다** — 흐름
  경로와 이중 렌더가 된다. 착수 전 **한글.app 실측 필요**: 코퍼스에 사례가 0건이라
  해시·골든이 "안 바뀌었다"만 말할 뿐 "맞다"를 증명하지 못한다
- **셀 안 개체는 같은 셀의 후속 문단을 아래로 밀지 않는다** — 측정
  (`floatingObjectHeight`)과 배치 (`laidOutContents`) 모두 문단 쌓기 커서를
  문단 높이만큼 전진시키므로 (`cursorY += content.totalHeight`), 개체보다 낮은
  문단 뒤에 다른 문단·중첩 표가 오면 그 위에 겹쳐 그려진다. 원래부터 있던
  설계이지 #91 하한의 결함이 아니다 — 흐름 비소비를 정하는 지점은
  `HwpParagraphObjectCollector`의 `advancesCursor` (R30 #1: 떠 있는 개체는
  저작 위치라 흐름을 소비하지 않는다) 이고, 하한은 셀이 개체를 담는 높이만
  보장한다. 고칠 때 **`.topAndBottom` (자리 차지) 한정**일 것 — `.square`
  (어울림) 는 한글이 텍스트를 개체 **옆으로** 흘리므로 아래로 밀면 옆자리가
  빈 띠로 남아 없던 오차가 생긴다. 자기 문단과의 겹침은 규약상 정상이라
  (위 "앵커 규칙") 대상이 아니다. 착수 전 **한글.app 실측 필요** (자리 차지
  개체 + 후속 텍스트가 든 셀) — 픽스처 코퍼스에는 사례가 없다 (noori에서
  개체를 가진 셀 3곳이 전부 단일 문단). 측정·배치 중 한쪽만 고치면 위 셀
  높이 항목의 측정 ≡ 배치 일치가 깨진다
- 페이지보다 큰 표 row 슬라이스는 문단을 라인 단위로 나눠 이월하지만 (절단선은
  라인 경계로 정렬), 라인 캐시 없는 문단·조각 경계의 중첩 표는 위 조각에 통째로 남는다.
  절단선 정렬(`lineAlignedCut`)과 조각 슬라이스(`slicedParagraph`)는 **같은
  전진량 함수**(`lineAdvances`)를 쓰고 둘 다 첫 미적합 라인에서 멈춘다 — 등분
  근사나 `for...where` 필터를 쓰면 절단선과 조각 경계가 어긋난다. 정렬은
  고정점까지 반복하되 pass 상한(32)을 두고, 초과하면 미정렬 `cutY`로 폴백한다
  (엇갈린 라인 그리드로 pass당 0.5pt씩만 내려가는 조작 문서의 로드 지연 차단)
- 페이지/단 경계로 분할된 문단의 컨트롤은 마지막 조각 처리 후 방출된다 —
  앞 조각에 앵커된 각주/메모가 마지막 조각의 페이지에 귀속되고, treatAsChar
  개체는 흐름 폴백된다. 근본 원인: 컨트롤 수집 (collectFootnotes/collectMemos/
  appendControlBlocks)이 placeParagraphText 뒤에 오는데 앞 조각 페이지는
  cacheCurrentPage에서 paintList까지 확정돼 사후 귀속이 불가능하다. 조각
  단위 방출은 분할 경로 전반 (flow split·단 밴드·절대 캐시 run)의 수술이라
  후속 과제 — 조각 라인 origin이 rebase되지 않아 (base-relative delta 규약)
  inlineAnchorMap 산식도 함께 바꿔야 한다
- treatAsChar 줄 중간 앵커는 분할되지 않은 문단 블록에서만 동작한다
  (다단에서 라인 분할된 문단의 개체는 흐름 위치 폴백)
- 그림 효과 중 PATTERN8x8 (효과 4)은 미지원 — 원본으로 렌더
- 글자 장식: 밑줄/취소선/음영/그림자/외곽선/양각·음각/강조점/첨자 렌더.
  양각·음각은 밝은/어두운 오프셋 사본 3-pass 근사, 강조점은 항상 채운 점
  (속 빈 동그라미/곡절 모양 미세분화). 이탤릭 페이스 없는 한글 폰트는
  기울임 매트릭스 근사 (`HwpTextRunBuilder.copy(_:adding:)`)
- 변경 내용 추적: 삭제된 텍스트는 BodyText가 아니라 **ViewText 스토리지**
  (표시용 본문)에 있다 — `HwpFile.displaySectionArray`가 ViewText 우선으로
  렌더 본문을 고른다 (한글.app 동작). 표식은 PARA_RANGE_TAG (kind 16 삽입 /
  17 삭제)로 오고 `HwpTextRunBuilder`가 빨강 밑줄/취소선으로, 문단 왼쪽 변경
  막대는 `appendTrackChangeBarIfNeeded`가 그린다. 작성자별 색 구분은 없음
  (항상 빨강)
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
  근사 배치한다. 감추기 (표 145 pghd·표 132 구역 정의)의 머리말/꼬리말/쪽 번호
  비트만 적용되고, 바탕쪽/테두리/배경 비트는 해당 렌더가 없어 무시된다.
  용지 방향은 세로 저장 + 넓게 선언일 때만 축을 바꾼다 — 가로 픽스처를 확보하면
  한글 저장 규약을 실측해 확정할 것
- 단 종류 (일반/배분/평행)와 맞쪽 방향은 미세분화 — 밴드가 닫힐 때 항상 배분,
  방향은 왼쪽/오른쪽만; 다단에서 페이지에 걸쳐 분할된 문단의 각주는 마지막
  조각의 페이지에 귀속된다
- `HwpPaginator`는 재진입 actor다 (base부터): `page(at:)`를 병렬로 직접 부르면
  같은 문단이 중복 배치될 수 있다 — `HwpDocumentActor.buildDocument`처럼
  순차 호출을 유지할 것

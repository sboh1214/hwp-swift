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
셀 문단 전부가 캐시로 측정된 셀은 저작된 셀 높이 (표 80)를 그대로 신뢰한다.

**셀 안 그림**: 셀 문단의 그림 컨트롤은 `HwpCellImage` (표-로컬 rect)로
셀 콘텐츠에 배치되고 페이지 흐름을 소비하지 않는다 (한글.app 실측: noori
3쪽 — 흐름 방출이면 큰 그림이 페이지를 밀어낸다). row 분할 시 함께 이동.

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
- `AnyHwpBlock.payload` — 종류별 상세 결과: `.table(HwpTableFrame)` / `.textbox` / `.footnote` / `.shape(HwpShapeGeometry)` / `.image(HwpImageBlockInfo)`. payload 내부 좌표는 **블록-로컬** (footnote 의 separator 만 페이지 좌표)
- `AnyHwpBlock.source` — `HwpBlockSource(controlInstanceId/paragraphId)`: 편집 기능이 렌더 결과에서 CoreHwp 모델로 돌아가는 참조
- `AnyHwpBlock.hyperlinkURL` — block-level. `HwpPaginator.hyperlinkURL(in:)` 이 top-level 및 nested paragraph 양쪽에서 추출
- 하이퍼링크 방출은 **스팬 우선**이다: `%hlk` 필드 스팬이 있으면 글리프 rect로만 방출하고, 스팬이 없는 컨테이너(표/글상자/각주) 문단만 문단 rect 폴백으로 담는다. 모델의 `hyperlinkURL`은 스팬 유무와 무관하게 채워지므로 폴백 측에서 `HwpDrawnTextLayout.hyperlinkRegions`로 게이트해야 앞뒤 평문이 링크로 표시되지 않는다 (hit tester의 `spanAwareHyperlinkURL`과 같은 규약)
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
  — 한쪽 모드에서 영영 실행되지 않는 스위트가 생긴다. 대신 렌더 해시는 모드별
  기준선 파일 (opt-in `<id>.json` / 기본 `<id>-nohancom.json`)로 양쪽을 각각
  잠그고, 블록 스냅샷·fidelity는 양 모드에서 성립하는 좌표·임계를 쓴다.
  전역 등록은 하지 않는다 (결정론 테스트 조회 오염 방지; `testDeterministic`은
  이 인덱스 자체를 끔). 이름 매칭은 name table 기본 + 로컬라이즈 이름 (한글) 둘 다.
  `HwpFontResolver.resolve` 는 매칭 결과를 (faceName, alternatives, script, size)
  키로 캐시. 해석 순서: 원문 이름 → `HwpFontMap.candidates(forFaceName:)` 폴백
  (원문 이름 → 정규화 이름 (`-`/`#` 접두 제거 + 공백 제거) 순) → 문서가 선언한
  대체/기반 글꼴 (아래 항목) → script 폴백. 각 후보는 시스템 → (opt-in 일 때만)
  한컴 번들 순으로 조회한다. 명조 계열은 AppleMyungjo, 고딕 계열은
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
  읽는다). 속성 쪽도 같은 성질이라 `attributes(forShapeId:shape:script:)` 의
  `shape` 는 **그 `shapeId` 로 만든 것**이어야 한다 — 키에 shape 내용이 없다.
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
  모드). 회귀 가드는 `HwpTextRunBuilderTests` 의 캐시 5종 (캐시/무캐시 문자열
  동치, 히트·미스 카운트, script 키 분리, 변경추적 마크 비오염, 탭 스톱
  재사용) — 캐시를 건드리면 `hitCount`/`missCount` (테스트 전용 관측점) 로
  단언할 것
- 실측 튜닝 상수는 `Tuning/HwpRenderTuning.swift` 에 근거 주석과 함께 —
  값 변경은 fidelity 전수 + 블록 스냅샷 + 실물 대조 필수 (값 핀:
  `HwpRenderTuningTests`). 차트 투영 기하 (`HwpChartPainter`)와 각주 예약
  근사 (`HwpPaginator`)는 예외로 in-place
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
- 셀 안 글상자/도형 (그림 제외)은 여전히 페이지 흐름 블록으로 방출된다
  (셀 위치가 아닌 흐름 위치 — 그림처럼 셀 콘텐츠로 옮기는 것은 후속 과제)
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

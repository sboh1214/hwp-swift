# HwpKitNative

플랫폼 브릿지 target (AppKit + UIKit). **SwiftUI import 금지.** HwpKit target 이 이 위에서 SwiftUI 래핑.

## 구조

```
HwpKitNative/
├── Platform/PlatformTypes.swift    # typealias (PlatformView/Color/Image/Font) — 뷰 chrome + provider가 사용
├── HwpDocumentViewSupport.swift    # macOS/iOS 뷰 공통 @MainActor 정적 헬퍼 — 선택 오버레이,
│                                   #   contentsScale 산식/일괄 갱신, 페이지 chrome, 메모 패널 레이어,
│                                   #   이미지 공급자, 프로그레시브 판정, Array[safe:] (#if 없이 양쪽 컴파일)
├── Rendering/HwpPageLayer.swift    # CALayer + paint list executor (Core Text, drawImageReference)
├── Rendering/HwpPageImageProvider.swift  # HwpImageStore + HwpImageCache + HwpImageAdapter 연결
├── Rendering/HwpDecodeThrottle.swift     # 동시 디코드 상한 3 (provider 전역 static)
├── Rendering/HwpImageStyleRenderer.swift # 표 107 crop/밝기/명암/효과 (CGImage.cropping + CoreImage)
├── Rendering/HwpPDFRenderer.swift  # CGPDFContext 스트리밍 기록 (HwpKit의 HwpPDFExporter가 감싼다)
├── macOS/HwpDocumentNSView.swift   # NSScrollView + 레이어 가상화 (magnification pinch zoom)
├── macOS/HwpDocumentNSViewSelection.swift  # 마우스 드래그 선택 + Cmd+C/Cmd+A/우클릭 Copy
├── iOS/HwpDocumentUIViewSelection.swift    # 롱프레스 선택 + 엣지 오토스크롤 + 편집 메뉴
├── macOS/HwpCenteringClipView.swift # 문서가 뷰포트보다 작을 때 중앙 정렬 클립 뷰
├── iOS/HwpDocumentUIView.swift     # UIView + UIScrollView (pinch zoom 내장)
├── Cache/HwpImageCache.swift       # LRU actor (256MB cap) — 뷰가 provider에 주입
└── Concurrency/HwpDocumentActor.swift  # parse/layout dispatch actor
```

양쪽 정렬 재조판 (HwpWordJustification)은 `HwpKitCore/Text/HwpWordJustification.swift`로 이동했다.

## 이미지 렌더 경로

1. paginator가 `.drawImageReference(binItemId:rect:)` 명령을 방출 (비트맵 없음)
2. 뷰가 document 변경 시 `HwpPageImageProvider(store: document.imageStore, cache: imageCache)` 생성해 레이어에 주입
3. `HwpPageLayer.draw` 가 `cachedImage` 동기 조회 → 없으면 로딩 표시 + `requestImage` (async 디코드: `HwpImageCache.fetch` → `HwpImageAdapter.decode`)
4. 디코드 완료 시 `onImageResolved` → main queue에서 레이어 `setNeedsDisplay`
5. 이미지는 flipped context 보정 (`drawFlippedImage`)으로 그린다 — 지우면 상하 반전

**캐시 계약** (`HwpImageCache`, public actor라 provider보다 오래 살거나 여러 provider에 주입될 수 있다):

- 캐시 값은 `HwpCachedImage` (비트맵 + **다운샘플 전 원본 픽셀 크기**). crop 좌표는 원본 픽셀 기준이라, 크기를 provider 로컬에 두면 warm 캐시 히트에서 스케일 기준이 사라져 잘못 잘린다
- `fetch`는 같은 key를 병합(coalesce)한다. 취소는 **대기자 참조 카운트**로 전파해 마지막 대기자가 사라질 때만 디코드를 취소한다 — 한 호출자의 취소로 공유 태스크를 죽이면 남은 호출자가 nil을 받아 영구 실패로 기록된다
- `clear()`는 in-flight 디코드를 취소하므로 그 nil은 **디코드 실패가 아니다**. provider는 fetch 전후 `purgeGeneration()`을 비교해 purge 중 취소를 `failedKeys`에 넣지 않는다 (넣으면 그 변형이 provider 수명 내내 placeholder)
- provider의 `finishRequest`는 세대 가드를 **최상단**에 둔다. 구세대 완료가 신세대 요청의 `inFlightKeys`/`activeTasks`를 지우면 중복 디코드·미추적 태스크가 생긴다 (구세대 정리는 `cancelOutstanding` 몫)

### 화면 없는 경로 (프리디코드, #74)

`requestImage`는 **draw가 다시 불릴 것을 전제로 한 fire-and-forget**이다 — 완료 통보는 `onImageResolved` → 레이어 재드로우로만 소비된다. PDF 내보내기·썸네일처럼 재드로우가 없는 경로는 그 루프를 못 쓰므로 `resolveImage(for:style:) async` / `predecodeImageReferences(in:) async`로 **확정을 직접 기다린다** (`HwpPageImageProvider`의 확장으로 갈라 둔다 — 뷰 경로와 섞이면 어느 쪽이 재드로우를 전제하는지 읽어 낼 수 없다).

여기서 유일하게 어려운 것은 **영구 대기를 만들지 않는 것**이다. 백프레셔가 세 겹이라 요청이 조용히 사라질 수 있다: 진행 상한 12 초과분은 디퍼드 큐(cap 64)로 가고, 그 큐가 만석 + 전부 pin이면 **드롭**된다 (축출 대상이 없어서). 드롭된 요청은 확정 통보를 영영 못 받는다.

- 그래서 대기자는 두 축으로 깬다 — 변형별 확정 통보(`settleWaiters`)와 **진행 토큰**(`progressToken`, 요청 하나가 확정될 때마다 증가). 변형이 진행·디퍼드 어디에도 없으면 드롭으로 보고 토큰이 움직일 때까지 기다렸다 다시 넣는다. 드롭은 "진행 중 요청이 12개 있다"는 뜻이므로 확정은 반드시 온다
- 토큰 스냅샷은 `requestImage` **전에** 뜬다. 드롭 판정과 대기 등록 사이에 끼어든 확정을 놓치면 아무도 깨우지 않는다
- 드롭과 **축출**은 다르다 (#74 리뷰). 드롭은 등록 **전에** 걸러지지만, 디퍼드 큐가 만석일 때의 축출은 이미 등록된 대기자의 변형을 큐에서 빼 간다 — 그 변형엔 `finishRequest`가 영영 오지 않으므로 `enqueueDeferred`가 축출 대상의 대기자를 함께 꺼내 `.untracked`로 깨운다 (락 밖에서). 진행 12 + 디퍼드 64를 넘는 동시 요청에서만 성립하지만, 그때 대기는 **영구**다
- 확정됐다가 바이트 예산으로 **축출된** 변형은 재시도하지 않고 nil이다. 재요청하면 동시 해석자끼리 서로를 밀어내는 라이브락이 된다 — 그 페이지를 온전히 그려야 하는 경로는 draw 전에 `unsettledImageVariants(in:)`로 확인한다 (아래 PDF 절)
- **"확정"은 기록이 있을 때만이다** (#74 리뷰 2차). 캐시 purge에 취소된 디코드는 `resolved`에도 `failedKeys`에도 안 들어가는데(R67 — 재시도 가능으로 남겨야 한다) 그것을 `.settled`로 깨우면 위 라이브락 컷이 예산 축출로 오분류해 재시도 없이 nil을 준다. `finishRequest`는 `image != nil || recordsFailure`일 때만 `.settled`로, 아니면 `.untracked`(재시도)로 깨운다
- continuation 재개는 **반드시 lock 밖**에서 (`takeWaiters` → `resume`). 재개가 같은 락을 다시 잡는 경로(`resolveImage` 루프)로 이어진다
- `cancelOutstanding`은 대기자 전원을 `.untracked`로 깨운다 — 요청 상태를 비웠으니 확정 통보를 받을 주체가 없다
- `predecodeImageReferences`는 **진행 상한 몫(12)씩 나눠** 요청한다. 한 번에 전량을 넣으면 초과분이 굳이 드롭 → 재시도 경로를 밟는다
- 호출 **전에** `setPinnedImages(HwpPageImageProvider.imageVariantKeys(in:))`로 고정할 것. 안 하면 먼저 디코드된 대형 이미지가 draw 전에 바이트 예산(256MB)으로 축출된다
- 스로틀(limit 3)은 **provider 전역 static**이라 export가 화면 뷰어와 슬롯을 공유한다. export 중 스크롤이 느려지는 것은 설계상 불가피하고, 취소는 스로틀 대기자에게 전파된다
- 테스트 헬퍼 `FixturePreview.resolveImageReferences`의 폴링 + 2초 타임아웃이 이 API로 대체됐다. 다만 **대기만 위임하고 확정 여부는 하네스가 다시 본다** (#74 리뷰 5차) — 프리디코드는 예산 축출된 변형을 미해결로 남기므로, 그대로 그리면 회색 로딩 사각형이 렌더 해시·골든·fidelity 기준선에 **정답으로 기록된다**. 라이브러리 쪽 `unsettledImageVariants`와 같은 판정이고 디코드 실패를 빼는 것도 같다
- 가드는 `Tests/HwpKitNativeTests/HwpPageImageProviderTests.swift`의 9종 — 확정 대기·페이로드 없음·취소 반환에 더해 **진행 상한(12) 초과 프리디코드**·**디퍼드 드롭 복구**·**디퍼드 축출 깨우기**·예산 축출의 관측 가능성·디코드 실패 제외·**purge 뒤 재시도**. 뒤 넷이 이 설계의 전부라 앞 셋만 있으면 스위트가 초록인 채로 영구 대기가 남는다. 축출 깨우기 테스트는 `maximumInFlight = 0`으로 확정을 **동결**해 경합 없이 그 상태를 만든다 (한도 3종이 인스턴스 프로퍼티인 이유) — 회귀 시 행(hang) 대신 실패로 끝나도록 대기는 전부 상한이 있다

## PDF 내보내기 (HwpPDFRenderer)

`HwpPageLayer.draw(in:)`를 **그대로** 쓴다 — 화면과 같은 paint list, 같은 조판이다. 페이지마다 새 레이어를 만들고 `beginPDFPage`에 `page.size` mediaBox를 넘긴다.

- flip은 **무분기**다. macOS의 독립 레이어는 `contentsAreFlipped() == false`라 스스로 뒤집고, iOS는 CGPDFContext가 y-up(`ctm.d > 0`)이라 같은 가지로 들어온다
- mediaBox는 `CGRect`를 **값째 담은 CFData**여야 한다 (참조 전달이 아니다). 형식이 틀리면 CG가 조용히 기본 상자를 쓴다 — 구역별 용지 크기·방향이 다른 문서에서만 드러나므로 `multi-section` 픽스처가 가드
- 메모 패널(`HwpPage.memoPanel`)은 종이 밖 편집 화면 장식이라 `page.paintList`만 그리는 이 경로에서 자연히 빠진다 (한글의 인쇄 뷰·PrvImage와 같다)
- 이미지는 `document.imageStore`로 **문서 전용 provider와 전용 캐시**를 새로 만든다. provider만 새로 만드는 것으론 부족하다 — 비트맵을 들고 있는 것은 `HwpImageCache`이고 그 키가 **`binItemId` 하나**라, 캐시를 문서 간에 공유하면 2번 문서의 1번 이미지가 1번 문서 것으로 히트한다. 그래서 `cache:` 주입 파라미터를 두지 않는다 (#74 리뷰 — 두면 호출자가 그 오염을 만들 수 있는데 막을 방법이 없다)
- 바이트 예산(256MB)은 **끄지 않는다**. 뷰의 하드 상한은 축출된 pin을 다음 재드로우가 되살린다는 전제 위에 있고 여기엔 그 재드로우가 없지만, 상한을 끄면 한 페이지 작업셋(변형당 ≤67MB × 개수)이 무제한이 되어 조작 문서가 프로세스를 고갈시킨다 (#74 리뷰 2차 — 한때 껐다가 되돌렸다). 대신 프리디코드 **뒤에** `unsettledImageVariants(in:)`로 잔존을 확인하고, 비어 있지 않으면 `pageImagesExceedMemoryBudget(pageIndex:)`로 **실패한다** — 회색 로딩 사각형이 박힌 PDF를 성공으로 돌려주는 것보다 낫다. 디코드 실패는 이 판정에서 빠진다 (뷰와 같이 플레이스홀더가 정답이라, 손상된 그림 하나로 문서 전체를 못 내보내면 안 된다)
- PDF 페이지는 기본이 투명이라 흰 종이를 먼저 깐다. 안 깔면 배경을 뷰어·프린터가 정해 종이 은유가 깨진다
- **목적지에 직접 쓰지 않는다** (#74 리뷰 2차). `CGDataConsumer(url:)`는 **생성 순간** 대상 파일을 0바이트로 자르므로(실측), 기존 PDF를 덮어쓰는 중에 취소·실패하면 사용자의 이전 파일이 복구 불가로 사라진다. 임시 파일에 완성한 뒤 `replaceItemAt`(없으면 `moveItem`)으로 옮기고, 실패 경로는 임시 파일만 지운다 — 목적지를 건드리는 순간은 **성공했을 때뿐**이다. 열리지 않는 PDF가 남지 않는다는 원래 성질도 그대로다. **스테이징 자리는 목적지와 같은 볼륨이어야 한다** (#74 리뷰 3차): `replaceItemAt`은 두 항목이 같은 볼륨일 것을 요구해 앱 임시 디렉터리에 두면 외장 드라이브의 기존 파일 덮어쓰기가 EXDEV로 실패한다 (실측: `NSPOSIXErrorDomain 18 "Cross-device link"`). `.itemReplacementDirectory`를 `appropriateFor:`로 잡아 해결하되, 그것도 실패하면 앱 임시로 폴백해 **신규 생성만은 살린다** (`moveItem`이 크로스 디바이스를 복사로 처리한다). CI가 두 번째 볼륨을 마운트하지 못해 **테스트가 없다** — 디스크 이미지로 손으로 잰다
- **설치 전에 산출물을 열어 본다** (#74 리뷰 4차). CG는 쓰기 실패를 **로그로만** 알린다 — `endPDFPage`·`closePDF`가 `Void`라 디스크가 차도 `write`가 정상 종료하고 절단 파일이 남는다 (실측: 6MB 볼륨에 11MB PDF → 열리지 않는 5.2MB 파일, 예외 없음). 그대로 옮기면 멀쩡하던 기존 PDF가 못 여는 파일로 바뀌면서 호출자는 성공을 받는다. `install`이 `CGPDFDocument`로 열고 페이지 수를 대조해 `incompleteOutput`으로 실패한다. 검증은 **`install` 안에** 둔다 — 밖에 두면 호출을 빠뜨려도 단위 테스트가 통과한다 (실제로 그랬고, 무력화 실험이 그 구멍을 드러냈다)
- 취소 확인은 **검증과 교체 사이에도** 한다 (#74 리뷰 5차) — 산출물 검증은 1,030쪽이면 짧지 않아 그 구간에 도착한 취소가 어디에서도 안 걸리면 목적지가 교체된다
- 취소 확인은 페이지 루프 안뿐 아니라 **`closePDF()` 뒤에도** 한다 (#74 리뷰). 마지막 페이지의 draw·진행 콜백에서 들어온 취소는 다음 반복이 없어 루프 안 확인이 보지 못하고, 그대로 성공으로 끝나면 호스트가 사용자가 취소를 누른 뒤 저장 패널·인쇄를 연다

## CRITICAL — macOS 좌표계 flip

`CALayer.draw(in:)` 는 **macOS 에서 기본 bottom-up (y+ 위) ctx, iOS 에서 top-down** 을 전달한다. 단, macOS 에서 조상 계층의 geometry flip 횟수가 홀수면 (isFlipped NSView 안 등) CA 가 이미 top-down 으로 보정한다.

`HwpPageLayer.draw(in:)` 은 `#if os(macOS)` 에서 **`contentsAreFlipped()` 가 false 일 때만** 수동으로 CTM 을 뒤집어 항상 top-down 을 보장한다. 레이어 자체에 `isGeometryFlipped = true` 를 켜면 안 된다 — flipped 조상 뷰와 합쳐져 **이중 flip (짝수) → 페이지가 상하 반전**된다 (실제로 겪은 버그).

macOS 페이지 레이어는 `HwpFlippedContentView` (isFlipped=true, NSScrollView documentView) 에 붙는다. NSClipView 는 documentView 의 flippedness 를 미러링하지만, `contentsAreFlipped()` 런타임 가드가 조상 flip 홀짝 변화를 동적으로 보정하므로 안전하다.

`drawTextLines` 의 CT flip (`translateBy` + `scaleBy(x: 1, y: -1)`) 과 `drawFlippedImage` 는 top-down 정규화 이후를 전제로 하므로 그대로 유지.

## CRITICAL — contentsScale (Retina 선명도)

`CALayer.contentsScale` 기본값은 1.0 — 설정하지 않으면 Retina 에서 1x 래스터를 확대해 **글씨가 흐릿해진다** (실제로 겪은 버그). 두 뷰 모두 `effectiveContentsScale` (backing/screen scale × max(1, zoom), 상한 4× — 산식은 `HwpDocumentViewSupport.effectiveContentsScale`) 을 레이어 생성 시와 zoom/backing 변경 시 적용한다 (macOS: `viewDidChangeBackingProperties`, iOS: `didMoveToWindow` + `scrollViewDidEndZooming`). 일괄 갱신은 `HwpDocumentViewSupport.updateContentsScale` — 메모 패널 레이어도 페이지와 함께 재래스터한다 (macOS·iOS 통일됨).

## 줄 배치 캐시 (HwpPageLayer)

`.drawText` 조판 결과 (`HwpDrawnTextLayout.lines`) 를 레이어 인스턴스 안에 캐시한다 — 재드로마다 framesetter 를 다시 돌리지 않는다. 재드로는 흔하다: contentsScale 변경 (핀치 줌 종료·Retina), bounds 변경 (`needsDisplayOnBoundsChange`), 이미지 디코딩 완료·디퍼드 용량 확보 콜백. 줄 기하는 pt 단위라 이 중 **어느 것도 캐시를 무효화하지 않는다** — 그게 이 캐시의 요점이다. `drawText` 는 조회 (`cachedDrawnLines`) · 순수 조판 (`typesetLines`) · 렌더 (`drawTextLines`) 셋으로 쪼개져 있어, 배치가 `pageHeight`·`bounds`·`contentsScale` 과 무관하다는 사실이 구조로 드러난다.

- **키는 `paintList.commands` 의 인덱스**다. NSAttributedString 의 `ObjectIdentifier` 를 쓰면 안 된다: `drawPlaceholder` 가 draw 마다 임시 문자열을 만들어, 해제된 주소가 재사용되면 같은 rect 의 플레이스홀더끼리 엉뚱한 히트로 **조용한 오조판**이 난다. 인덱스 키는 `drawPlaceholder` 가 커맨드 인덱스를 갖지 않으므로 캐시 우회를 코드가 아니라 구조로 강제한다.
- **무효화는 `paintList` didSet 의 `removeAll()`**, 그리고 히트 시 페이로드 재검증 (`===` + origin/lineWidth) 이 2차 방어선이다. 후자가 필요한 이유: `init(layer:)` 의 대입은 `super.init` 이전이라 didSet 이 발화하지 않고, 프로그레시브 갱신 경로는 양쪽 뷰의 `paintList == nil` 가드 때문에 기존 레이어에 재대입하지 않는다.
- **CA 사본 (`init(layer:)`) 은 캐시를 복사하지 않는다** — 빈 캐시로 시작해 스스로 채운다.
- **상한 초과 시 축출이 아니라 삽입 중단**이다. draw 는 커맨드를 항상 같은 순서로 전량 훑으므로 FIFO 축출은 워킹셋이 상한보다 큰 페이지에서 히트율 0% + 매 draw 전량 재삽입이 된다. 상한은 엔트리 수가 아니라 누적 줄 수 (`cachedLineBudget` 기본 8,192 — 엔트리 하나가 `maximumLineFrames` = 100,000 줄까지 담을 수 있어 엔트리 수 상한은 CTLine 보유량을 못 묶는다). 인스턴스 프로퍼티라 테스트가 값을 낮춰 초과 경로를 작은 문서로 재현한다.
- **락 (`NSLock`) 은 딕셔너리 조회/저장 순간에만 잡는다** — CoreText 조판·CTLineDraw 중에는 보유 금지 (그 아래로 텍스트 호출이 추가돼도 재진입 데드락이 없게). `paintList` didSet 의 `setNeedsDisplay()` 도 락 밖이다. 이 락은 Dictionary 동시 변형이라는 메모리 비안전만 막을 뿐 레이어를 thread-safe 하게 만들지 않는다 (클래스가 `@unchecked Sendable`).
- 텍스트 선택의 `HwpSelectionGeometry` 도 같은 `[HwpDrawnLine]` 을 캐시하지만 **문서 스코프 + FIFO 512** 로 별개다 (그쪽은 랜덤 액세스라 FIFO 가 맞는다). 두 캐시는 서로 독립이다.
- HwpKitCore 의 `HwpTextAttributeCache` 와는 **층**이 다르다 — 그쪽은 문서 빌드 (paginate) 때 `NSAttributedString` 을 만드는 **입력** (글자 모양별 속성 사전) 을 메모하고, 이 캐시는 그 결과 문자열의 **draw 때 조판**을 메모한다. 서로 참조하지 않고 이득도 겹치지 않으므로 (단계가 다르다) 하나가 있다고 다른 하나가 불필요해지지 않는다.
- 회귀 가드는 `Tests/HwpKitNativeTests/HwpPageLayerCacheTests.swift` (7종). **기존 뷰 테스트는 전부 draw 1회라 콜드 경로만 타서 캐시 버그를 잡지 못한다** — 캐시를 건드리면 draw 를 2회 이상 돌리고 `typesetCount` / `cachedDrawnLineEntryCount` (테스트 전용 관측점) 로 단언할 것.
- 실측 (macOS, 재드로 20회, 캐시 무력화 A/B): Column 1쪽 681.0 → 368.9ms (1.85x, 조판 220 → 0회), noori 3쪽 913.9 → 596.4ms (1.53x, 1360 → 80회 — 잔여 80 = 플레이스홀더 4개 × 20회로 설계대로 우회). 남는 시간은 CTLineDraw·장식이라 캐시가 줄일 몫이 아니고, 레이어가 객체째 폐기·재생성되는 스크롤은 콜드 경로라 이득이 없다.

## HwpDocumentActor.buildDocument

- `HwpFile` (URL/Data) 을 background executor 에서 `options: .viewer` (rawPayload opt-out) 로 파싱
- `HwpIndex` + `HwpImageStore` + `HwpPaginator` 구축
- `page(at:)` 를 페이지 nil 이 나올 때까지 loop 하여 `HwpDocument.pages` 채움
- `await paginator.unsupportedElements()` 로 `HwpDocument.unsupportedElements` 채움 — 실제 `HwpUnsupportedDetector` walk (top-level + nested ctrls) 는 HwpKitCore 의 `HwpPaginator.collectUnsupported`/`walkUnsupported` 가 pagination 중 수행
- 반환된 `HwpDocument` 는 fully-paginated (View 는 lazy 재요청 안 함)
- 취소 확인은 루프 안뿐 아니라 **마지막 await 뒤에도** 한다 — 완료된 task의 `.value`는 취소돼도 throw하지 않으므로, terminal 구간(마지막 `page(at:)`·`unsupportedElements()`)에서 도착한 교체를 놓치면 호출자가 superseded 문서를 받는다

### 프로그레시브 로딩 (`loadDocumentUpdates`)

- `AsyncThrowingStream<HwpDocumentSnapshot, Error>` — 첫 `firstBatch`(기본 1) 쪽 확정 즉시 1차 스냅샷, 이후 `batchSize`(기본 24) 쪽마다, 완료 시 최종 스냅샷 (`isComplete == true`, `unsupportedElements` 포함) 방출. `loadDocument` 는 이 스트림의 최종 스냅샷만 반환하는 래퍼로 동작 — 최종 결과는 동치 (loadToken 제외)
- 스냅샷은 같은 `imageStore` 를 공유하고, `HwpDocumentMetadata.loadToken` (UUID) 으로 연속성 표시. 뷰의 `document` didSet 이 `HwpDocumentViewSupport.isProgressiveUpdate` (같은 loadToken + 페이지 증가) 로 **증분 적용** (레이어·스크롤 유지, 크기·가시 범위만 확장) vs **전체 리셋** 을 분기. 첫 페이지 표시가 전량 로드 완료를 기다리지 않는다 (1,030쪽 실문서 23.8s → 첫 페이지 ~3.2s)

## 텍스트 선택

- 선택 상태/지오메트리는 HwpKitCore의 `HwpSelectionController`/`HwpSelectionGeometry` (플랫폼 중립). 줄 배치는 렌더러와 같은 `HwpDrawnTextLayout`을 공유해 하이라이트가 화면과 일치한다.
- 하이라이트는 `CAShapeLayer`를 **HwpPageLayer의 sublayer**로 부착 — 조상 flip 기하를 상속하므로 top-down rect를 그대로 쓴다 (자체 flip 금지).
- 머리말/꼬리말/쪽 번호는 `AnyHwpBlock.role == .pageChrome`으로 선택·복사에서 제외.
- macOS: mouseDown/Dragged/Up 드래그 (하이퍼링크 click recognizer는 무이동 클릭만 발화라 공존), Cmd+C·우클릭 Copy, Cmd+A/`selectAll(_:)` 전체 선택. iOS: 롱프레스 단어 선택 → 드래그 확장 (뷰포트 엣지 44pt 존에서 CADisplayLink 오토스크롤) → UIEditMenuInteraction Copy/Select All.

## 레이어 가상화

- **visible ± 2 페이지만** sublayer 로 유지
- `updateVisiblePages(range:)` 가 diff 로 add/remove
- 스크롤/줌 시 자동 호출 (macOS: 클립 뷰 `boundsDidChangeNotification`, iOS: delegate)
- iOS: `UIScrollView.viewForZooming` = contentView (page layers 컨테이너)
- macOS: `NSScrollView.allowsMagnification` (0.25–5.0) 이 핀치 줌 담당 — `zoomScale` 은 magnification 을 읽고 쓰는 계산 프로퍼티 (별도 배율 상태 없음). 라이브 핀치 종료 (`didEndLiveMagnifyNotification`) 시에만 `contentsScale` 재적용
- macOS: `NSClickGestureRecognizer` 로 hit test (documentContentView 에 부착), iOS: `UITapGestureRecognizer`
- iOS 초기 위치: SwiftUI `makeUIView` 는 bounds 0 에서 document 를 대입하므로 센터링을 첫 non-zero `layoutSubviews` 로 **예약**한다. 그 창에 들어온 명시 페이지 요청(`scrollToPage`)은 인덱스를 함께 예약해 센터링 대신 그 페이지로 복원하고, 문서가 **전체 교체**되면 예약 인덱스를 버린다 (옛 문서 기준 페이지에서 열리는 것 방지). 같은 문서 재전달(`document == oldValue`)은 스크롤 유지가 의도라 예약도 보존
- 페이지 좌표 → 인덱스 변환은 macOS·iOS 모두 **이진 탐색** (`pageOriginsY` 오름차순). 선택 드래그·오토스크롤은 프레임마다 호출되므로 선형 스캔이면 만 쪽 문서에서 비용이 페이지 수에 비례한다

## Callback 발화 규약

| Callback | 발화 시점 |
|---|---|
| `onHyperlinkTapped(url)` | tap/click 이 `.hyperlink` 블록 프레임을 hit 했을 때 |
| `onPageChanged(page)` | `updateVisiblePages` 가 visible range 를 갱신할 때 |
| `onZoomChanged(scale)` | 핀치/스크롤 줌으로 배율이 변했을 때 (버튼 줌 echo 는 가드로 차단) |
| `onUnsupportedElement(element)` | 양쪽 플랫폼: document `didSet` 시 `unsupportedElements` 순회 (콜백은 document 할당보다 먼저 배선됨) |

## 안티 패턴

- 페이지 스크롤 시 새 페이지 fetch 를 main thread 에서 sync — 반드시 `HwpDocumentActor.page(at:)` async 호출
- 300 페이지 문서를 열 때 모든 페이지 layer 를 persistent 로 유지 — 메모리 폭발. `visible ± 2` 정책 유지
- Dark mode 에서 페이지 배경/텍스트 색을 반전 — HWP 저자 의도 그대로 렌더 (whitepaper metaphor)

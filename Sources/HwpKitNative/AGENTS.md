# HwpKitNative

플랫폼 브릿지 target (AppKit + UIKit). **SwiftUI import 금지.** HwpKit target 이 이 위에서 SwiftUI 래핑.

## 구조

```
HwpKitNative/
├── Platform/PlatformTypes.swift    # typealias (PlatformView/Color/Image/Font) — 뷰 chrome + provider가 사용
├── HwpSelectionHandleGeometry.swift # 선택 핸들 순수 기하 (#if 밖 — iOS 잡은 커버리지 미수집, #84)
├── HwpDocumentViewSupport.swift    # macOS/iOS 뷰 공통 @MainActor 정적 헬퍼 — 선택 오버레이,
│                                   #   contentsScale 산식/일괄 갱신, 페이지 chrome, 메모 패널 레이어,
│                                   #   이미지 공급자, 프로그레시브 판정, Array[safe:] (#if 없이 양쪽 컴파일)
├── HwpDocumentAccessibility.swift  # 페이지별 합성 AX 요소 보관함(제네릭) + 모델 합성 진입점 (#79, #if 밖)
├── Rendering/HwpPageLayer.swift    # CALayer + paint list executor (Core Text, drawImageReference)
├── Rendering/HwpPageImageProvider.swift  # HwpImageStore + HwpImageCache + HwpImageAdapter 연결
├── Rendering/HwpDecodeThrottle.swift     # 동시 디코드 상한 3 (provider 전역 static)
├── Rendering/HwpImageStyleRenderer.swift # 표 107 crop/밝기/명암/효과 (CGImage.cropping + CoreImage)
├── Rendering/HwpPageBitmapRenderer.swift # 페이지 → CGImage (PDF와 그리기 몸통·확정 계약 공유, #76)
├── Rendering/HwpPageThumbnailRenderer.swift # 문서 스코프 축소판 (쪽 순회 규율 + 직렬화, #76)
├── Rendering/HwpPDFRenderer.swift  # CGPDFContext 스트리밍 기록 (HwpKit의 HwpPDFExporter가 감싼다)
├── macOS/HwpDocumentNSView.swift   # NSScrollView + 레이어 가상화 (magnification pinch zoom)
├── macOS/HwpDocumentNSViewGeometry.swift   # 가시 범위·보존 창·페이지 프레임
├── macOS/HwpDocumentNSViewSelection.swift  # 마우스 드래그 선택 + Cmd+C/Cmd+A/우클릭 Copy
├── macOS/HwpDocumentNSViewSearch.swift     # 검색 오버레이 2벌 + 매치 노출 스크롤 (#75)
├── macOS/HwpDocumentNSViewAccessibility.swift  # NSAccessibilityElement 합성 (#79)
├── iOS/HwpDocumentUIViewAccessibility.swift    # UIAccessibilityElement 합성 (#79)
├── iOS/HwpDocumentUIViewGeometry.swift     # 위와 대칭 (#75에서 UIView 본체에서 분리)
├── iOS/HwpDocumentUIViewSelection.swift    # 롱프레스 선택 + 엣지 오토스크롤 + 편집 메뉴 + collapsed 정리
├── iOS/HwpDocumentUIViewSelectionHandles.swift # 선택 끝점 핸들 뷰·배치·드래그 (#84)
├── iOS/HwpDocumentUIViewSearch.swift       # 위와 대칭 (#75)
├── macOS/HwpCenteringClipView.swift # 문서가 뷰포트보다 작을 때 중앙 정렬 클립 뷰
├── iOS/HwpDocumentUIView.swift     # UIView + UIScrollView (pinch zoom 내장)
├── Cache/HwpImageCache.swift       # LRU actor (256MB cap) — 뷰가 provider에 주입
├── Cache/HwpThumbnailCache.swift   # 축소판 비트맵 — 삽입순 + 바이트 예산 결정적 축출 (#76)
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
- 드롭과 **축출**은 다르다 (#74 리뷰). 드롭은 보통 등록 **전에** 걸러지지만, 디퍼드 큐가 만석일 때의 축출은 이미 등록된 대기자의 변형을 큐에서 빼 간다 — 그 변형엔 `finishRequest`가 영영 오지 않으므로 `enqueueDeferred`가 축출 대상의 대기자를 함께 꺼내 `.untracked`로 깨운다 (락 밖에서). 진행 12 + 디퍼드 64를 넘는 동시 요청에서만 성립하지만, 그때 대기는 **영구**다
- **드롭 경로에도 대기자가 있을 수 있다** (#74 리뷰 9차). `finishRequest`는 디퍼드에서 꺼낸 재시도를 **락 밖에서** 다시 요청하는데(`handler`·`capacityHandler`가 그 사이에 돈다), 그 틈에 다른 요청이 두 큐를 채우면 그 재요청이 드롭 분기로 간다. 그 변형의 대기자는 디퍼드에 있던 동안 등록된 것이라 축출과 같은 처리를 받아야 한다 — 드롭 분기도 대기자를 함께 내보낸다. "첫 요청엔 대기자가 없다"는 직관이 **디큐된 재시도에만 깨진다**
- 확정됐다가 바이트 예산으로 **축출된** 변형은 재시도하지 않고 nil이다. 재요청하면 동시 해석자끼리 서로를 밀어내는 라이브락이 된다 — 그 페이지를 온전히 그려야 하는 경로는 draw 전에 `unsettledImageVariants(in:)`로 확인한다 (아래 PDF 절)
- **그 컷은 확정 에포크가 받쳐야 성립한다** (#74 리뷰). 위 판정은 `awaitVariantSettled`가 `.settled`를 줄 때만 서는데, 그러려면 대기자 등록이 `finishRequest`보다 앞서야 한다. 요청과 등록 **사이**에 확정이 지나가고 그 결과가 다른 변형의 삽입에 축출되면 (자기 삽입은 `keeping:`이 막지만 남의 삽입은 못 막는다) 등록 측엔 `resolved`·`failedKeys`·`inFlightKeys`·`deferredVariants` 어디에도 흔적이 없어 `.untracked`로 새고, `didSettleOnce`가 서지 않아 컷이 통째로 우회된다. 변형별 `settleEpochs`를 요청 **전에** 스냅샷해 등록 시점과 비교하는 것이 그 창을 메운다 — 재시도 회차일수록 캐시가 뜨거워 `finishRequest`가 빨리 돌므로 창에 더 자주 걸린다. 에포크는 **기록된 확정**(`image != nil || recordsFailure`)에만 오른다: purge 취소를 세면 R67의 재시도 경로가 축출로 오분류된다. 고정 집합이 바뀔 때 함께 줄여야 한다 (`pruneSettleEpochs`) — 예산 축출된 변형은 `resolvedOrder`에도 없고 뷰 경로는 `retainOnlyImages`를 부르지 않아, 안 줄이면 문서 전체 변형 수만큼 쌓인다. **그 프루닝은 진행 중인 해석자의 변형을 남겨야 한다** (#74 리뷰 2차): 고정 집합은 뷰 스크롤로 수시로 바뀌는데, 해석자가 대기에 등록되기 **전** 구간에 그 항목이 지워지면 조회 기본값이 0이라 스냅샷이 0이던 첫 해석에서 비교가 같아져 확정이 없던 것처럼 보인다 — 방금 막은 컷이 그대로 다시 뚫린다 (공유 provider에서 오프스크린 해석자가 도는 동안 뷰가 `setPinnedImages`를 부르는 형상). `activeResolvers`가 `resolveImage` 진입·이탈에 변형별 카운트를 두고 프루닝이 그것을 보존하며, 마지막 해석자가 떠날 때 작업셋 밖 항목을 그 자리에서 거둬 상한을 지킨다 (보호를 무기한 두면 프루닝이 무력해진다). 가드는 `Tests/HwpKitNativeTests/ImageSettleEpochTests.swift` (경합 자체는 이음매가 없어 재현 불가 — 컷이 기대는 성질만 잠근다. 보존 조건을 빼면 `testPruneKeepsEpochWhileResolverIsActive`가 `1 → 0`으로 실패한다 — 무력화 실험 확인)
- **"확정"은 기록이 있을 때만이다** (#74 리뷰 2차). 캐시 purge에 취소된 디코드는 `resolved`에도 `failedKeys`에도 안 들어가는데(R67 — 재시도 가능으로 남겨야 한다) 그것을 `.settled`로 깨우면 위 라이브락 컷이 예산 축출로 오분류해 재시도 없이 nil을 준다. `finishRequest`는 `image != nil || recordsFailure`일 때만 `.settled`로, 아니면 `.untracked`(재시도)로 깨운다
- continuation 재개는 **반드시 lock 밖**에서 (`takeWaiters` → `resume`). 재개가 같은 락을 다시 잡는 경로(`resolveImage` 루프)로 이어진다
- `cancelOutstanding`은 대기자 전원을 `.untracked`로 깨운다 — 요청 상태를 비웠으니 확정 통보를 받을 주체가 없다. 깨어난 `resolveImage`는 **재요청 없이 끝낸다** (#74 리뷰 7차): 해체는 store/cache 작업을 놓으려고 부르는 것인데 대기자가 다시 요청하면 그것을 되살린다. 판정은 `.untracked` 분기가 아니라 **시작 시점 세대와의 비교**여야 한다 — 해체는 확정 통보와 진행 토큰을 **둘 다** 깨우므로, 그때 `awaitProgress`에서 자던 해석자는 그 분기를 지나지 않는다
- `predecodeImageReferences`는 **진행 상한 몫(12)씩 나눠** 요청한다. 한 번에 전량을 넣으면 초과분이 굳이 드롭 → 재시도 경로를 밟는다
- 호출 **전에** `setPinnedImages(HwpPageImageProvider.imageVariantKeys(in:))`로 고정할 것. 안 하면 먼저 디코드된 대형 이미지가 draw 전에 바이트 예산(256MB)으로 축출된다
- 스로틀(limit 3)은 **provider 전역 static**이라 export가 화면 뷰어와 슬롯을 공유한다. export 중 스크롤이 느려지는 것은 설계상 불가피하고, 취소는 스로틀 대기자에게 전파된다
- 픽스처 렌더 하네스의 폴링 + 2초 타임아웃이 이 API로 대체됐고(#74 리뷰 5차), #76에서 **확정 판정 자체가 라이브러리로 올라갔다** — `HwpPageBitmapRenderer.resolveImages(in:provider:policy:)`가 대기와 판정을 함께 소유하고 하네스는 `.fail` 정책을 고르기만 한다. 판정이 필요한 이유는 그대로다: 프리디코드는 예산 축출된 변형을 미해결로 남기므로, 그대로 그리면 회색 로딩 사각형이 렌더 해시·골든·fidelity 기준선에 **정답으로 기록된다**. 디코드 실패는 빠진다 (플레이스홀더가 정답이라 뷰와 같다)
- 가드는 `Tests/HwpKitNativeTests/HwpPageImageProviderTests.swift`의 9종 — 확정 대기·페이로드 없음·취소 반환에 더해 **진행 상한(12) 초과 프리디코드**·**디퍼드 드롭 복구**·**디퍼드 축출 깨우기**·예산 축출의 관측 가능성·디코드 실패 제외·**purge 뒤 재시도**. 뒤 넷이 이 설계의 전부라 앞 셋만 있으면 스위트가 초록인 채로 영구 대기가 남는다. 축출 깨우기 테스트는 `maximumInFlight = 0`으로 확정을 **동결**해 경합 없이 그 상태를 만든다 (한도 3종이 인스턴스 프로퍼티인 이유) — 회귀 시 행(hang) 대신 실패로 끝나도록 대기는 전부 상한이 있다

## 페이지 → 비트맵 (HwpPageBitmapRenderer, #76)

`HwpPage`를 `CGImage`로 만드는 프로덕션 경로. `HwpPageLayer.draw(in:)`가 뷰 계층 없이 임의 `CGContext`에 그리는 순수 오프스크린 렌더러라 가능하고, PDF 경로와 **그리기 몸통 한 자리를 공유한다** (`draw(page:in:provider:)` — 종이 배경 + 레이어 구성 + draw). 갈라 두면 배경·flip·레이어 필드 중 하나가 한쪽에서만 바뀐다.

- **확정 계약도 한 구현이다** — `resolveImages(in:provider:policy:)`가 `retainOnlyImages` → `predecodeImageReferences` → (`.fail`이면) `unsettledImageVariants` 순서를 소유하고, PDF는 그 `.unresolvedImages`를 `pageImagesExceedMemoryBudget(pageIndex:)`로 옮겨 담는다. 예산 둘을 함께 거는 자리도 `makeProvider(for:imageByteLimit:)` 하나다 (한쪽만 낮추면 상한이 두 배가 되는 실수를 구조로 막는다)
- **미확정 정책만 호출자마다 갈린다** (`HwpUnresolvedImagePolicy`). PDF·픽스처 하네스는 `.fail` — 산출물이 사용자 파일이거나 커밋된 기준선이라 회색 로딩 사각형이 정답으로 굳으면 안 된다. 축소판은 `.drawPlaceholder` — 보조 표시라 그림 하나 때문에 쪽 전체를 잃는 것이 더 나쁘다
- **`sourceRect`는 캔버스를 채울 페이지 영역**(top-down 페이지 좌표)이다. 기본값(페이지 전체)일 때 CTM이 **순수 스케일**이어야 커밋된 골든·픽셀 해시가 안 흔들린다 — 그래서 이동을 스케일 **뒤에** 걸어 페이지 단위로 해석시킨다. 장치 단위로 걸면 `pageH × (pxH / pageH) ≠ pxH`라 1e-13pt 이동이 남는다. 이 인자가 있는 이유는 하나뿐이다: 일부 저장본의 PrvImage가 확대·크롭 렌더라 `FixturePreview`의 `zoom`이 그 대조에 필요하다 (zoom배 = 좌상단 1/zoom 영역을 채우기). **유한성 검사는 `> 0`으로 부족하다**: NaN 원점은 크기를 건드리지 않아 통과하고, 무한 크기는 스케일을 0으로, 비정규 크기는 스케일을 무한으로 만든다. 그런 CTM에서 CG는 실패하지 않고 **아무것도 그리지 않은 흰 비트맵을 성공으로** 돌려주므로(실측: 세 입력 모두 `makeImage()` 성공 + 잉크 0), `SourceTransform`이 스케일·이동 성분까지 유한한지 본 뒤에야 그린다 — 아니면 빈 그림이 `.fail` 정책 경로의 기준선에 정답으로 굳는다
- 캔버스 전체를 먼저 흰색으로 깐 **뒤** 종이를 다시 깐다. `sourceRect`가 종이 밖으로 나가면 그 여백이 투명(0)으로 남아, 알파를 무시하고 읽는 소비자에게 검정이 된다
- **출력 픽셀에는 축별 상한이 있다** (`maximumPixelDimension` = 16,384, #76 리뷰) — 여기가 **픽셀 수를 문서가 정하는** 경로라서다. 근거와 층 구분(크기 헬퍼는 클램프·렌더러는 거부)은 루트 `AGENTS.md`의 "쪽 축소판". 클램프는 `Int(_:)` 변환 **전에** 한다: 그 변환이 범위 밖에서 트랩하므로 조작 문서의 종횡비와 `Int.max` 픽셀 폭이 둘 다 그리로 온다. 상한 안에서만 `pixelWidth * 4`가 안전하므로 그 가드는 `CGContext` 생성보다 **앞**이어야 한다. **면적 상한도 따로 있다** (`maximumPixelCount` = 16,777,216 = 64 MiB) — 축별 상한만 두면 **폭 하나짜리 요청**이 16,384²(1 GiB)로 가기 때문이다 (세로 페이지는 높이가 상한까지 클램프된다). 축별 검사를 **먼저** 통과시켜야 그 곱이 오버플로하지 않는다
- **검증은 공급자보다 먼저다** (`validatedGeometry`). 크기·기하는 순수 계산인데 `resolveImages` 뒤에 두면 확정적으로 실패할 요청이 페이지 그림을 전부 디코드한 뒤에야 거절되고, `.fail` 정책에서는 그 예산 압박이 `.unresolvedImages`를 먼저 던져 진짜 원인을 가린다. `rasterize`가 원시 정수가 아니라 `BitmapGeometry`를 받으므로 순서를 어길 수 없다 — 축소판 경로(`HwpPageThumbnailRenderer.image`)도 같은 함수를 디코드 앞에서 부른다
- **`FixturePreview.renderImage`가 이 API에 위임한다** — 그래야 렌더 가드 4층이 테스트 전용 사본이 아니라 출하되는 코드를 검사한다. 하네스에 남는 것은 `zoom`과 `.fail` 정책 선택뿐이다
- 가드는 둘로 갈린다. `HwpPageBitmapRendererTests`가 **렌더 계약**(픽셀 크기·상하 방향[잉크 비영은 반전을 통과시킨다]·`sourceRect` 기하·정책 두 갈래)을, `HwpPageBitmapRendererBoundsTests`가 **자원·정의역 경계**(종횡비 폭주·`Int.max` 픽셀 폭·총 면적·비유한 `sourceRect`·**검증이 디코드보다 먼저인지**)를 본다 — 마지막 것은 오류 **타입**으로 관측한다: 같은 문서·같은 예산이 유효한 크기에서는 `.unresolvedImages`를 내므로, 잘못된 크기에서 입력 오류가 나오면 디코드 전에 끝났다는 뜻이다 — 뒤엣것은 정상 경로에서 보이지 않아 골든·해시가 영영 못 잡는 축이다. 둘 다 골든이 **못 보는 것**만 재고, 픽스처 렌더 회귀는 커밋된 골든이 본다

## 쪽 축소판 (HwpPageThumbnailRenderer, #76)

문서 하나의 쪽 축소판을 만들고 들고 있는다. `HwpPageBitmapRenderer.render`를 쪽마다 부르는 것과 **다르다** — 그쪽은 호출마다 공급자·캐시를 새로 만들어 원본 디코드를 처음부터 다시 한다.

- **쪽 순회 규율은 PDF와 같다**: 쪽마다 `retainOnlyImages`. `setPinnedImages`만 쓰면 그것이 부르는 축출이 예산 초과 시에만 돌아 이전 쪽 래스터가 잔류하고, 문서를 훑는 동안 상주량이 한도까지 자란다 (**unpin은 해제가 아니다**). 축소판은 정의상 쪽 순회다
- **요청은 직렬화한다** (`HwpDecodeThrottle(limit: 1)` 재사용 — 취소 시 슬롯 없이 false를 주는 계약이 그대로 필요하다). `retainOnlyImages`가 공급자 전역이라 두 쪽을 동시에 그리면 한쪽이 다른 쪽의 확정된 변형을 draw 직전에 버린다. 게이트를 잡은 **뒤에** 캐시를 다시 보는 것도 그래서다 — 기다리는 사이 같은 쪽이 그려졌을 수 있다 (그리드 셀이 스크롤로 두 번 나타나는 흔한 형상)
- **문서 교체 판정은 뷰와 같은 함수**(`HwpDocumentViewSupport.isProgressiveUpdate`)를 쓴다. 갈리면 뷰는 증분인데 축소판만 전부 버려 1,030쪽이 배치마다 다시 그려진다. 전체 교체에서만 공급자·캐시를 새로 만든다 — `cancelOutstanding`은 요청 상태만 비우고 디코드 결과·실패 키를 지우지 않으므로, `binItemId` 캐시 오염 방지는 **교체**가 담당한다
- **세대 가드가 캐시 삽입을 막는다**: 그리는 동안 문서가 바뀌면 그 비트맵은 옛 문서의 쪽이다. 넣으면 다른 문서의 쪽이 그 자리에 굳는다 (`HwpImageCache`가 `binItemId` 하나로 키를 잡는 것과 같은 성격의 오염)
- **취소 검사는 네 자리다** — ③만 원래 있었고 #76 리뷰가 ①②④를 더했다. ① 진입 — 첫 캐시 조회가 게이트보다 **앞**이라, 검사를 뒤에 두면 이미 그린 쪽을 요청한 취소된 셀은 취소 경로를 아예 지나지 않고 성공한다. ② 게이트 획득 직후 — 슬롯을 **넘겨받은 뒤**의 취소를 스로틀은 무시하고 호출부에 맡긴다 (`HwpDecodeThrottle.cancelWaiter` 주석: release가 이양한 대기자의 늦은 취소). ③ 이미지 확정 직후 — `resolveImages`의 await에서 돌아온 자리다. ④ 래스터화 직후 — 동기 구간이라 그 사이 도착한 취소는 여기서만 잡힌다. **④의 결과는 온전한 이미지다**: ③을 이미 지났으므로 회색 사각형이 굳는 것을 막는 것은 취소가 아니라 **세대 가드**이고, ④는 "취소는 아무것도 캐시하지 않는다"를 문자 그대로 지킬 뿐이다. 결정적으로 재현되는 것은 ①뿐이다 (②는 이음매 없는 경합, ④는 동기 구간)
- **스로틀(limit 3)은 전역이다** — 축소판이 가시 페이지와 슬롯을 나눠 쓴다. 그래서 셀별 취소가 성능 장치가 아니라 계약이다 (`Sample`의 `.task`가 셀이 사라질 때 끊는다). 이것을 재는 테스트는 없다
- 축소판 캐시(`Cache/HwpThumbnailCache.swift`)는 **삽입순 + 바이트 예산 결정적 축출**이다. NSCache를 쓰지 않는 이유는 provider와 같다 (예산 안이어도 즉시 축출 → 재요청 루프, #3). 키에 픽셀 폭이 들어가는 것은 작은 축소판이 큰 요청에 히트해 흐릿하게 남는 것을 막기 위해서고, 정리는 **한 패스**다 (`retainOnlyImages`와 같은 이차 함정)
- 가드는 `HwpPageThumbnailRendererTests`(순회 규율·캐시 동일 인스턴스·프로그레시브 유지 vs 전체 교체 폐기, 그리고 **위 두 줄을 각각 잠그는** 취소 2종(`testCancelledRequestFailsWithoutCaching`은 캐시가 빈 경로, `testCancelledRequestDoesNotReturnAnAlreadyRenderedThumbnail`은 **캐시 히트** 경로 — 후자가 없으면 ① 검사를 지워도 스위트가 초록이다)·세대 가드 2종 `testSupersededRenderResultIsNotCached`/`testRenderStartedBeforeADocumentSwapIsNotCached`)와 `HwpThumbnailCacheTests`(축출 순서·재삽입 바이트·선형성·**혼자 예산을 넘는 항목은 삽입 즉시 축출하지 않기** — provider의 `evictOverBudget(keeping:)`와 같은 이유로, 축출하면 그 쪽이 매 요청마다 재렌더다). 공개 표면 골든은 `Tests/HwpKitTests/HwpPageThumbnailsTests.swift` — 커밋된 렌더 골든이 **1쪽을 한 번도 그리지 않으므로**(`specs`가 2쪽 이후만 고른다) 그 구멍을 여기서 메운다

## PDF 내보내기 (HwpPDFRenderer)

`HwpPageLayer.draw(in:)`를 **그대로** 쓴다 — 화면과 같은 paint list, 같은 조판이다. 페이지마다 새 레이어를 만들고 `beginPDFPage`에 `page.size` mediaBox를 넘긴다.

- **입력 계약은 `validateInput` 하나가 소유한다** (#74 리뷰). 빈 문서(`emptyDocument`)와 프로그레시브 중간 스냅샷(`incompleteDocument`)을 함께 막는다 — 진입점이 `render`·`renderData` 둘이라 가드를 복제하면 한쪽이 조용히 뚫린다 (`emptyDocument` 가드가 실제로 그렇게 복제돼 있었다). 미완성 문서가 위험한 이유는 아래 산출물 검증을 **통과하기** 때문이다: 접두만 담긴 PDF도 열리고 그 페이지 수도 맞아 `incompleteOutput`이 잡지 못한다. 이미지 예산 초과를 실패로 끝내는 것과 같은 이유다 — 페이지가 통째로 빠진 PDF는 회색 사각형보다 나쁜 조용한 손실이다
- flip은 **무분기**다. macOS의 독립 레이어는 `contentsAreFlipped() == false`라 스스로 뒤집고, iOS는 CGPDFContext가 y-up(`ctm.d > 0`)이라 같은 가지로 들어온다
- mediaBox는 `CGRect`를 **값째 담은 CFData**여야 한다 (참조 전달이 아니다). 형식이 틀리면 CG가 조용히 기본 상자를 쓴다 — 구역별 용지 크기·방향이 다른 문서에서만 드러나므로 `multi-section` 픽스처가 가드
- 메모 패널(`HwpPage.memoPanel`)은 종이 밖 편집 화면 장식이라 `page.paintList`만 그리는 이 경로에서 자연히 빠진다 (한글의 인쇄 뷰·PrvImage와 같다)
- 이미지는 `document.imageStore`로 **문서 전용 provider와 전용 캐시**를 새로 만든다. provider만 새로 만드는 것으론 부족하다 — 비트맵을 들고 있는 것은 `HwpImageCache`이고 그 키가 **`binItemId` 하나**라, 캐시를 문서 간에 공유하면 2번 문서의 1번 이미지가 1번 문서 것으로 히트한다. 그래서 `cache:` 주입 파라미터를 두지 않는다 (#74 리뷰 — 두면 호출자가 그 오염을 만들 수 있는데 막을 방법이 없다)
- 페이지마다 `retainOnlyImages`로 **이전 페이지 래스터를 버린다** (#74 리뷰 6차). `setPinnedImages`만 쓰면 안 된다 — 그것이 부르는 축출은 예산 초과 시에만 동작하므로 예산 안에서는 이전 페이지가 그대로 남아, 문서를 훑는 동안 상주량이 한도까지 자란다 (**unpin은 해제가 아니다**). 캐시도 같은 예산으로 만든다: 기본값을 두면 provider 변형 예산과 독립으로 쌓여 상한이 두 배가 된다. 실제 보장은 "현재 페이지 변형 + 원본 캐시(≤ 같은 예산)"이지 1페이지 몫이 아니다. 이 정리는 **한 패스**여야 한다 (#74 리뷰): 축출마다 `firstIndex` + `remove(at:)`을 부르면 스캔·이동이 각각 O(N)이라 제거 수에 대해 이차가 된다. 변형 키가 (binItemId, 자르기·밝기·명암·효과)라 한 페이지가 같은 그림의 crop 인스턴스를 수천 개 참조하면 그 크기에 닿고, 특히 **고정 변형이 앞쪽에 모이면** 매 축출이 그 접두를 다시 훑어 상수까지 커진다 (릴리스 실측, 앞 절반 고정: N=4,000 203ms · 8,000 874ms · 16,000 **3,611ms** — 배가 될 때마다 4배. 한 패스 뒤 16,000이 0.003s). `evictOverBudget`도 같은 형태라 함께 고쳤다 — 그쪽은 예산 아래로 내려가면 멈추지만 스캔은 같은 접두를 반복한다. 가드는 `Tests/HwpKitNativeTests/ImagePruningTests.swift` (바이트 해제·축출 순서 보존·선형성)
- 바이트 예산(256MB)은 **끄지 않는다**. 뷰의 하드 상한은 축출된 pin을 다음 재드로우가 되살린다는 전제 위에 있고 여기엔 그 재드로우가 없지만, 상한을 끄면 한 페이지 작업셋(변형당 ≤67MB × 개수)이 무제한이 되어 조작 문서가 프로세스를 고갈시킨다 (#74 리뷰 2차 — 한때 껐다가 되돌렸다). **과금 대상은 그 변형이 자기 몫으로 든 래스터뿐이다** (#74 리뷰 3차): 디코드 원본은 캐시가 `binItemId` 하나로 한 번만 보유해 변형들이 공유하므로, 그것까지 변형마다 세면 같은 바이트가 중복 계상돼 **메모리에 넉넉히 들어가는 페이지가 초과로 판정된다** (실측: 4MB 원본의 100×100 crop 4장이 8MB 예산에서 16MB로 계상돼 2장 축출 → 유효한 내보내기가 `pageImagesExceedMemoryBudget`으로 중단). 층 구분은 위에 적은 보장 그대로다 — 변형은 provider 예산, 원본은 캐시 예산. 그래서 `max(styled, source)`로 "안전하게" 되돌리면 안 된다 (가드: `Tests/HwpKitNativeTests/ImageByteAccountingTests.swift` — 무력화 실험에서 그 복원 시 둘 다 실패한다). 대신 프리디코드 **뒤에** `unsettledImageVariants(in:)`로 잔존을 확인하고, 비어 있지 않으면 `pageImagesExceedMemoryBudget(pageIndex:)`로 **실패한다** — 회색 로딩 사각형이 박힌 PDF를 성공으로 돌려주는 것보다 낫다. 디코드 실패는 이 판정에서 빠진다 (뷰와 같이 플레이스홀더가 정답이라, 손상된 그림 하나로 문서 전체를 못 내보내면 안 된다)
- PDF 페이지는 기본이 투명이라 흰 종이를 먼저 깐다. 안 깔면 배경을 뷰어·프린터가 정해 종이 은유가 깨진다
- **목적지에 직접 쓰지 않는다** (#74 리뷰 2차). `CGDataConsumer(url:)`는 **생성 순간** 대상 파일을 0바이트로 자르므로(실측), 기존 PDF를 덮어쓰는 중에 취소·실패하면 사용자의 이전 파일이 복구 불가로 사라진다. 임시 파일에 완성한 뒤 `replaceItemAt`(없으면 `moveItem`)으로 옮기고, 실패 경로는 임시 파일만 지운다 — 목적지를 건드리는 순간은 **성공했을 때뿐**이다. 교체에는 `backupItemName`을 준다 (#74 리뷰 8차): 교체가 원본을 옮긴 **뒤** 실패하면 목적지가 비는데 Foundation은 그 자리를 error userInfo로만 알려 주므로, 이름을 우리가 정해 두고 실패 시 되돌린다 (`restoreBackup`). **백업이 남아 있으면 목적지에 무엇이 있든 원본이 이긴다** (#74 리뷰 11차): 교체는 스테이징을 설치한 **뒤**(메타데이터 복사·백업 정리)에도 실패할 수 있어 그때 목적지엔 새 PDF가 있는데, 그것을 두고 백업만 지우면 실패를 보고하면서 이전 파일을 잃는다. "목적지가 살아 있으면 새 결과를 지킨다"는 직관이 **실패 경로에서는 정확히 반대**다 백업 이름은 목적지 이름에서 파생하지 않는다 — 긴 파일명에 접미사를 붙이면 255바이트를 넘겨 정상 경로가 깨진다. 실패 사유도 `fileWriteFailed(path:reason:)`로 함께 전한다 열리지 않는 PDF가 남지 않는다는 원래 성질도 그대로다. **스테이징 자리는 목적지와 같은 볼륨이어야 한다** (#74 리뷰 3차): `replaceItemAt`은 두 항목이 같은 볼륨일 것을 요구해 앱 임시 디렉터리에 두면 외장 드라이브의 기존 파일 덮어쓰기가 EXDEV로 실패한다 (실측: `NSPOSIXErrorDomain 18 "Cross-device link"`). `.itemReplacementDirectory`를 `appropriateFor:`로 잡아 해결하되, 그것도 실패하면 앱 임시로 폴백해 **신규 생성만은 살린다** (`moveItem`이 크로스 디바이스를 복사로 처리한다). CI가 두 번째 볼륨을 마운트하지 못해 **테스트가 없다** — 디스크 이미지로 손으로 잰다
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

선택·검색 하이라이트 오버레이 (`CAShapeLayer`) 는 그 일괄 갱신 대상이 아니라 `updateHighlightOverlays` 가 **매 호출** 부모 페이지 레이어의 `contentsScale` 을 물려준다 — 벡터 path 라 페이지와 다른 배율로 래스터하면 확대에서 가장자리가 뭉개진다. **물려받기만 하므로 배율 갱신이 오버레이를 다시 칠해 줘야 한다** (`updateLayerContentsScale` 이 선택·검색 갱신을 함께 부른다, #75 리뷰): 줌 종료는 페이지 레이어 배율만 바꾸고, macOS 는 가시 범위가 같으면 `clipViewBoundsDidChange` 가 조기 반환하며 iOS 는 `scrollViewDidZoom` 이 **배율 갱신보다 먼저** 오버레이를 칠하므로, 그 두 줄이 없으면 하이라이트가 옛 배율로 남아 흐려진다. 가드는 양 플랫폼의 `testOverlayScaleFollowsPageLayerAfterScaleChange`.

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
- `await paginator.outline()` 로 `HwpDocumentMetadata.outline` (개요·책갈피 탐색 목록, #77) 채움 — 수집은 HwpKitCore 의 `HwpPaginator.collectOutline`/`HwpOutlineCollector` 가 pagination 중 수행. **이것만 조판 도중에 물어도 의미가 있다** (확정된 접두를 준다) — 그래서 아래 중간 스냅샷이 이 값만 싣는다. 책갈피가 이제 이 목록의 재료라 `HwpUnsupportedDetector` 에서 빠졌다 (`"알 수 없음: bookmark"` 항목이 더는 오지 않는다)
- 반환된 `HwpDocument` 는 fully-paginated (View 는 lazy 재요청 안 함)
- 취소 확인은 루프 안뿐 아니라 **마지막 await 뒤에도** 한다 — 완료된 task의 `.value`는 취소돼도 throw하지 않으므로, terminal 구간(마지막 `page(at:)`·`outline()`·`unsupportedElements()`)에서 도착한 교체를 놓치면 호출자가 superseded 문서를 받는다

### 프로그레시브 로딩 (`loadDocumentUpdates`)

- `AsyncThrowingStream<HwpDocumentSnapshot, Error>` — 첫 `firstBatch`(기본 1) 쪽 확정 즉시 1차 스냅샷, 이후 `batchSize`(기본 24) 쪽마다, 완료 시 최종 스냅샷 (`isComplete == true`, `unsupportedElements` 포함) 방출. `loadDocument` 는 이 스트림의 최종 스냅샷만 반환하는 래퍼로 동작 — 최종 결과는 동치 (loadToken 제외)
- **중간 스냅샷의 두 목록은 정책이 갈린다** (#77): `unsupportedElements` 는 최종 스냅샷에만 오지만 `metadata.outline` 은 **이 스냅샷이 담은 쪽까지의 접두**를 싣는다 (조판이 배치 도중에도 쪽을 확정할 수 있어 수집기가 `pages` 보다 앞설 여지가 있으므로 `prefix` 로 자른다 — **방어**다: 실제 위반은 재현하지 못했다, 근거는 루트 `AGENTS.md`. `filter` 가 아닌 이유는 발행분이 접두여야 `ordinal` 이 흔들리지 않기 때문이다) — 사이드바는 로딩 중에 쓰라고 있는 물건이라 1,030쪽이 다 배치될 때까지 비워 두면 쓸모가 없고, 수집이 append-only 라 `ordinal` 이 스냅샷 사이에서 움직이지 않아 `List` 신원이 흔들리지 않는다 (근거는 루트 `AGENTS.md` 의 "개요·책갈피 탐색 (#77)"). 가드는 `HwpDocumentLoaderProgressiveTests` 의 **짝 지은 두 테스트** — 한쪽만 두면 "정책이 갈린다"는 사실 자체가 안 잠긴다. outline 은 증분 판정에 관여하지 않는다 (`isProgressiveUpdate` 는 loadToken 과 페이지 수만 본다)
- 스냅샷은 같은 `imageStore` 를 공유하고, `HwpDocumentMetadata.loadToken` (UUID) 으로 연속성 표시. 뷰의 `document` didSet 이 `HwpDocumentViewSupport.isProgressiveUpdate` (같은 loadToken + 페이지 증가) 로 **증분 적용** (레이어·스크롤 유지, 크기·가시 범위만 확장) vs **전체 리셋** 을 분기. 첫 페이지 표시가 전량 로드 완료를 기다리지 않는다 (1,030쪽 실문서 23.8s → 첫 페이지 ~3.2s)

## 검색 하이라이트 (#75)

- 오버레이 딕셔너리는 **2벌**이다 (`searchMatchLayers` / `currentSearchMatchLayers`). 헬퍼가 페이지당 오버레이 하나를 재사용하므로 한 벌로 두 번 칠하면 두 번째 호출이 첫 번째의 path 를 덮는다.
- z-순서는 `HwpOverlayZ` 로 **명시**한다 (search 10 / current 20 / selection 30). 부착이 `addSublayer` 한 줄이고 이미 붙어 있으면 다시 붙이지 않으므로, 명시하지 않으면 첫 부착 순서가 그대로 고착돼 가상화로 재실체화한 페이지만 겹침 색이 뒤바뀐다. 선택이 최상단인 것은 사용자가 직접 만든 것이라 자동 하이라이트에 가리면 안 되기 때문이다. 선택 **끝점 핸들**(#84)은 이 표에 없다 — 페이지 레이어의 sublayer 가 아니라 스크롤 뷰의 형제 UIView 라 겹침 순서가 뷰 계층으로 정해진다.
- `fillColor` 는 **매 호출** 갱신한다. 문서 교체가 딕셔너리를 비우지 않아 오버레이가 재사용되는데, 생성 분기에서만 대입하면 옛 색이 그대로 남는다 (선택만 있을 때도 있던 결함).
- 색은 **고정 sRGB** 다 (`HwpSearchHighlightStyle.default`). appearance/trait 변경 훅이 이 타깃에 하나도 없어 동적 색은 `.cgColor` 변환 시점에 굳고 다크 모드 전환 후 낡은 색이 남는다.
- **가시 범위가 같은 스크롤 틱은 건너뛴다** — 양 플랫폼 모두 (macOS `clipViewBoundsDidChange`, iOS `scrollViewDidScroll` 의 `activeVisibleRange` 가드, #75 리뷰). 오버레이 재구축은 페이지마다 매치 전량(상한 5,000)을 훑어 rect·CGPath 를 새로 만드는데 페이지 레이어는 스크롤과 함께 움직이므로 대부분 같은 결과를 다시 만드는 일이다. **줌은 가드하지 않는다** — 프레임이 바뀐다. 대가로 같은 페이지 안의 매치 이동은 저절로 갱신되지 않으므로 `onCurrentMatchChanged` 에서 명시적으로 부른다.
- 탐색(`onCurrentMatchChanged`)은 오버레이를 **한 번만** 다시 만든다 — `scrollToMatch` 가 끝에서 `updateVisiblePages` 를 돌려 이미 칠했으면 (반환값 `true`) 호출부가 건너뛴다 (#75 리뷰). 무조건 부르면 페이지별 매치 전량 필터와 CGPath 재구성을 탐색마다 두 번 문다. 스크롤이 없었던 경우(매치 없음·범위 밖·iOS 첫 레이아웃 전)에만 직접 부른다. **`scrollToMatch` 안에서도 두 번이었다** (#75 리뷰 11차, 실측 2회): 쪽을 넘는 스크롤은 `scroll(to:)`·`setContentOffset` 이 **동기로** 스크롤 콜백(`clipViewBoundsDidChange`·`scrollViewDidScroll`)을 태워 이미 갱신하므로, 그 뒤 무조건 부르면 재구축이 2회다. 스크롤 **전** `activeVisibleRange` 를 잡아 두고 바뀌었으면 건너뛴다 — 같은 쪽 안의 이동은 그 콜백이 조기 반환하므로 그때만 직접 부른다 (그래서 이 두 경우를 "가시 범위가 바뀌었나" 하나로 가른다). 반환값은 **두 경우 모두 `true`** 다: 그 값은 "내가 칠했나"가 아니라 호출부가 중복을 건너뛰는 근거라, 콜백이 칠한 경우에 `false` 를 내면 `onCurrentMatchChanged` 가 세 번째 재구축을 붙인다. 기존 가드(`testNavigationRebuildsOverlaysOnce`)가 이걸 못 잡은 이유는 픽스처가 **한 쪽짜리** 문서라 같은 쪽 이동만 봤기 때문이다.
- **iOS 는 마지막 쪽도 첫 가시 쪽이 되도록 아래 여유를 둔다** (`trailingScrollExtent`, #75 리뷰). 없으면 문서 전체 오프셋 클램프가 페이지-로컬 목표를 끌어내려, 매치로 점프해도 앞 쪽이 첫 가시가 되고 그 쪽이 `currentPage` 로 보고된다 (마지막 쪽이 뷰포트보다 낮을 때 — 축소했거나 짧은 쪽). 모자란 만큼만, 콘텐츠가 뷰포트보다 클 때만 준다. **macOS 에는 아직 같은 보장이 없다** — `HwpCenteringClipView.constrainBoundsRect` 를 함께 고쳐야 해서 남겨 둔 비대칭이다.
- 단위 캐시 축출은 **이 계층이 소유**한다 — 유지 범위(가시 ±2쪽)를 아는 유일한 층이라 `HwpSearchController.retainedPageRange` 훅을 여기서 채우고, **가시 범위가 바뀔 때마다 `evictUnitsOutsideRetainedRange()` 를 직접 부른다** (오버레이를 그린 뒤에 — 먼저 버리면 곧 읽을 것을 버린다). 스캔 중 축출만으로는 상한이 서지 않는다 (#75 리뷰): 스캔이 끝난 뒤에도 하이라이트 조회가 페이지마다 단위를 다시 전개해 캐시에 넣으므로 1,030쪽을 훑으면 **매치가 있는 페이지 전부**가 남는다 (매치 없는 페이지는 `highlightRects` 의 빈 선택 가드에서 먼저 걸러진다).
- **세션 해체도 이 계층이 소유한다** (#75 리뷰). `searchController = nil` 이 `detach()` 를 부르고 SwiftUI 쪽 `dismantleNSView`/`dismantleUIView` 가 그것을 부른다 — 안 떼면 호스트가 `@State` 로 붙든 컨트롤러가 이 뷰의 선택 컨트롤러를, 그것이 다시 **문서 전체**(페이지·페인트 리스트·단위 캐시)를 잡는다. 새 문서를 열면 `attach` 가 옛 것을 떼므로 남는 경로는 **문서를 닫거나 재로드가 실패했을 때**다. 떼는 대상은 `isAttached(to:)` 로 **자기 것만** 고른다 — SwiftUI 가 새 뷰를 먼저 만들고 옛 뷰를 나중에 해체할 수 있어, 무조건 떼면 이미 새 뷰에 붙은 세션이 끊긴다. SwiftUI 를 거치지 않는 **직접 사용 경로**엔 `dismantle*` 이 아예 없으므로 양 뷰의 `deinit` 이 같은 일을 한다 (`HwpDocumentViewSupport.detachSearchSessionOnTeardown`) — `deinit` 은 nonisolated 이고 dealloc 이 메인에서 돈다는 보장도 없어 `@MainActor` 인 `detach()` 를 그 자리에서 못 부르니 참조만 넘겨 홉을 태우고, 거기서도 같은 동일성 가드를 지난다. **뗄 때는 이 뷰가 설치한 훅 셋(`onMatchesChanged`·`onCurrentMatchChanged`·`retainedPageRange`)도 함께 지운다** (`HwpDocumentViewSupport.removeSearchHooks`, #75 리뷰 13차) — 안 지우면 뗀 컨트롤러가 옛 뷰의 클로저를 들고 있다가, 재사용될 때 옛 뷰를 다시 칠하고 `retainedPageRange` 로 **새 지오메트리를 옛 가시 범위로 축출**한다 (곧 읽을 단위를 버려 성능이 조용히 나빠진다). 클로저는 동일성 비교가 안 되므로 "다른 뷰가 이미 재배선했는가"는 `isAttached(to:)` 가드로만 가른다 — 그래서 detach 와 훅 제거가 **같은 가드 안**에 있어야 한다.
- 하이라이트 **색 변경**은 컨트롤러가 `onMatchesChanged` 로 직접 통지한다 (#75 리뷰). 이 계층은 매치·현재 매치 콜백만 듣고 SwiftUI wrapper 는 컨트롤러 신원만 넘기므로, 색만 바뀐 순간에는 아무도 다시 칠하지 않는다.
- **매치 노출 스크롤(`scrollToMatch`)은 두 축이다.** 세로는 목표를 페이지 범위로 클램프해 **매치 페이지가 첫 가시 페이지**가 되게 한다 — 안 그러면 `currentVisiblePage()` 가 이웃 페이지를 가리켜 SwiftUI `currentPage` 왕복이 스크롤을 되튕긴다. 가로는 `horizontalOffset(toReveal:)` 이 **이미 뷰포트 안이면 현재 오프셋을 그대로 두고** 밖일 때만 뷰포트 가운데로 가져온다 — 매치마다 재조정하면 같은 단에서 다음 매치로 넘어갈 때 화면이 좌우로 흔들린다. 세로만 맞추면 뷰포트가 페이지(595pt)보다 좁을 때(iPhone·축소 안 한 창) 잘린 오른쪽의 매치로 점프해도 **카운터만 바뀌고 화면은 그대로**다. iOS 의 클램프(`clampedContentOffsetX`)는 선택 오토스크롤의 세로판과 같은 파일에 둔다.
- **오버레이 단언은 "보이는가"를 증명하지 못한다.** 위 결함이 있는 동안에도 부착·색·z-순서·세로 클램프 단언이 전부 초록이었다 — 그 단언들은 "레이어가 올바른가"만 본다. 발견은 **시뮬레이터 육안 확인**이었고, 게다가 오버레이 스위트가 macOS 전용이라 iOS 경로엔 단언 자체가 없었다 (`HwpDocumentUIViewSearchTests` 가 그래서 생겼다 — macOS 대응 스위트와 같은 계약을 건다). 회귀 테스트를 쓸 때 둘: 대상 rect 를 콘텐츠 **밖**에 두면 스크롤로 도달할 수 없어 계약이 성립하지 않으므로 "뷰포트보다 넓은 콘텐츠 + 콘텐츠 안의 화면 밖 rect"로 조건을 잡고, 배선을 보는 테스트는 `updateSearchOverlays()` 를 **직접 부르지 않는다** (부르면 콜백 배선 누락이 가려진다 — 초안에서 실제로 가려져 있었다).

## 텍스트 선택

- 선택 상태/지오메트리는 HwpKitCore의 `HwpSelectionController`/`HwpSelectionGeometry` (플랫폼 중립). 줄 배치는 렌더러와 같은 `HwpDrawnTextLayout`을 공유해 하이라이트가 화면과 일치한다.
- 하이라이트는 `CAShapeLayer`를 **HwpPageLayer의 sublayer**로 부착 — 조상 flip 기하를 상속하므로 top-down rect를 그대로 쓴다 (자체 flip 금지).
- 머리말/꼬리말/쪽 번호는 `AnyHwpBlock.role == .pageChrome`으로 선택·복사에서 제외.
- macOS: mouseDown/Dragged/Up 드래그 (하이퍼링크 click recognizer는 무이동 클릭만 발화라 공존), Cmd+C·우클릭 Copy, Cmd+A/`selectAll(_:)` 전체 선택. iOS: 롱프레스 단어 선택 → 드래그 확장 (뷰포트 엣지 44pt 존에서 CADisplayLink 오토스크롤) → **끝점 핸들 드래그로 재조정** (#84) → UIEditMenuInteraction Copy/Select All.
- collapsed 선택(양 끝점이 겹친 상태)은 제스처 끝에서 지운다 — 양 플랫폼 모두 (macOS `mouseUp`, iOS `clearCollapsedSelection()`). 안 지우면 `hasSelection` 이 false 인데 선택 객체만 남아 오버레이 갱신이 계속 돈다.

### 선택 끝점 핸들 (iOS, #84)

- **끌 수 있는 끝점은 언제나 `focus` 하나다.** 핸들을 잡는 순간 `HwpSelectionController.beginAdjusting(edge:)` 가 잡은 쪽을 focus 로, 반대쪽을 anchor 로 **한 번만** 바꾸고, 그 뒤 이동은 기존 `extend(to:)` 가 그대로 한다. 그래서 오토스크롤 틱에 "어느 끝점" 상태를 넣을 필요가 없다 (틱은 늘 focus 를 민다). 교환을 `.changed` 나 틱마다 부르면 매 프레임 anchor/focus 가 뒤집혀 끌던 끝점이 제자리를 맴돈다.
- **핸들 역할 뒤바뀜은 상태가 아니라 정규화의 결과다.** 시작 핸들을 끝 핸들 너머로 끌면 `range` 가 뒤집혀 잡고 있던 것이 '끝 핸들'이 된다 (UITextView 와 같은 동작). 두 핸들 뷰는 각각 `range.start`/`range.end` 에 고정 바인딩이므로, 뒤바뀐 뒤에는 **드래그를 소유한 뷰가 고정단으로 옮겨 간다** — 진행 중인 제스처는 뷰가 움직여도 계속 추적되므로 동작은 그대로다. 다만 그 뷰가 화면 밖으로 스크롤될 수 있어 숨김에 `isHidden` 이 아니라 `alpha` 를 쓴다 (alpha 0 은 히트 테스트에서 빠지면서 진행 중인 인식에는 영향이 없다).
- **핸들은 `contentView` 가 아니라 뷰 본체의 서브뷰다** (스크롤 뷰의 형제). 이 저장소에는 제스처 중재 코드가 한 건도 없어 (`require(toFail:)`·`UIGestureRecognizerDelegate` 0건) 중재 계층을 새로 세우는 대신 계층 배치로 푼다 — 히트 테스트가 핸들에서 끝나므로 스크롤 pan·핀치·롱프레스·탭이 그 터치를 아예 못 본다. 특히 탭 핸들러의 첫 분기가 `hasSelection → clear()` 라, 같은 계층에 뒀다면 **핸들을 톡 치는 순간 선택이 통째로 사라진다**. 덤으로 줌 transform 도 안 물려받아 배율 역보정 산식이 없다 (`contentView.convert(_:to:)` 가 배율과 오프셋을 함께 반영한다).
- 그래서 `HwpOverlayZ` 에 핸들 상수가 **없다** — 핸들은 페이지 레이어의 sublayer 가 아니라 UIView 라 z-순서 계약의 대상이 아니다.
- **겹친 그랩 영역은 subview 순서가 아니라 그립 거리로 가른다** (#84 리뷰). `point(inside:)` 가 프레임을 사방 `grabMargin`(11) 넓히므로 두 끝점이 **16.5pt**(그립 반지름 5.5 + 여유 11) 안으로 가까워지면 끝 핸들의 그랩 영역이 시작 그립을 통째로 덮는다 — 같은 줄이면 **세로는 언제나 덮는다** (끝 핸들 그랩 상단 = 시작 그립 상단 = 캐럿 상단 − 11) 이라 판별은 가로 하나뿐이다. UIKit `hitTest` 는 subview 역순이라 나중에 붙은 끝 핸들이 늘 이기고, 그러면 그 배율에서 **시작 끝점을 잡을 길이 사라진다**. 핸들은 줌 밖이라 크기가 화면 고정인데 캐럿 간격만 배율을 타므로 0.25x 에서는 문서 66pt(한글 6자) 선택까지 걸리고, 1x 에서도 한 글자면 걸린다. 그래서 각 핸들이 형제를 알고(`sibling`) 겹칠 때는 `HwpSelectionHandleGeometry.winsGrabContest` 로 **그립 중심이 가까운 쪽**이 가져간다. 두 그립은 캐럿 위·아래로 갈라져 있어(`handleFrame`) 끝점이 완전히 겹쳐도 `줄 높이 + 지름`만큼 떨어지므로 이 기준은 항상 답을 낸다.
- **그 술어는 반대칭이어야 한다** — 둘 다 true 면 subview 순서로 되돌아가 위 결함이 그대로고, 둘 다 false 면 터치가 스크롤 뷰로 새어 탭 핸들러의 `hasSelection → clear()` 가 **선택을 통째로 지운다** (원래 결함보다 나쁘다). 동점은 좌표가 아니라 **끝점 종류**로 가른다 (좌표로 가르면 양쪽이 같은 답을 낸다). 배선도 함께 봐야 한다 — `configureSelectionHandles` 의 `sibling` 대입 두 줄이 빠지면 `point(inside:)` 가 조기 반환해 판정이 **통째로 무동작**이 된다 (무력화 실험으로 확인: 그 두 줄을 지우면 `testOverlappingHandlesRouteEachTouchToItsOwnKnob` 이 실패한다).
- **갱신 진입점은 넷이고 하나가 예외다.** 선택 변경(`onSelectionChanged`)·가시 페이지 갱신(`updateVisiblePages`)·줌 종료 배율 재적용(`updateLayerContentsScale`) 셋은 `updateSelectionOverlays()` 를 지나므로 그 안에서 부른다. 스크롤만 `scrollViewDidScroll` 이 **`range != activeVisibleRange` 가드 앞에서** 직접 부른다 — 핸들은 줌 대상 밖에 살아 스크롤을 따라 움직이지 않는데, 가시 범위가 같은 스크롤은 그 가드에 걸려 아래로 못 내려간다.
- **뷰포트 밖 끝점의 핸들은 숨긴다** (가장자리 클램프 금지). 클램프하면 손가락이 엉뚱한 자리의 핸들을 잡아 선택이 튄다. 페이지 레이어가 축출돼도 캐럿 좌표는 지오메트리에서 나오므로 계산 자체는 살아 있다.
- **산식은 `#if os(iOS)` 밖에 둔다** (`HwpSelectionHandleGeometry`). iOS 잡은 `xcodebuild test` 만 돌고 커버리지를 수집하지 않으므로 (`--enable-code-coverage`·codecov 업로드는 macOS 잡 소속), 가드 안에만 사는 산식은 codecov patch 에 아예 안 잡힌다. `HwpDocumentViewSupport.effectiveContentsScale`·`autoscrollStep` 과 같은 틀이다.
- 상태는 값 타입 하나(`HwpSelectionInteractionState`)로 묶는다 — `HwpDocumentUIView` 타입 본문이 SwiftLint `type_body_length` **error** 임계(400)에 닿아 있어 저장 프로퍼티를 한 줄만 늘려도 Lint 잡이 종료 코드 2로 끝난다. 신규 상태만 묶는 게 아니라 기존 오토스크롤·편집 메뉴 상태까지 접어 본문을 **순감**시켰다 (400 → 399).
- **가시 판정에 `CGRect.intersects` 를 쓰면 안 된다** (`isCaretVisible`). 캐럿은 폭 0이라 `CGRect.isEmpty` 가 참이고 CG 의 교차 판정은 빈 사각형에 **항상 false** 를 준다 — 그대로 쓰면 뷰포트 한가운데 있는 캐럿의 핸들까지 전부 숨는다. 그래서 축별 비교를 손으로 쓰고, 가로는 경계에 정확히 걸친 캐럿을 살리려 `>=`/`<=` 다 (실측: 폭 0 캐럿이 뷰포트 오른쪽 끝에 있을 때 `intersects` 는 false, 이 술어는 true). 위 "뷰포트 밖은 숨긴다" 규칙이 실제로 작동하려면 이 한 줄이 필요하다.
- 가드: `HwpSelectionHandleGeometryTests`(14종 — 프레임·부품 배치, `handleFrame` ↔ `caretCenter` 왕복, 그랩 오프셋·여유, 빈 사각형 함정을 잠그는 `testCaretVisibilityDoesNotRideOnEmptyRectSemantics`, 겹침 판정 3종[그립 중심·**반대칭**·가까운 그립 승리]) + `HwpDocumentUIViewSelectionTests`(14종 — 뷰 배선, 그중 `testOverlappingHandlesRouteEachTouchToItsOwnKnob` 이 실제 히트 테스트로 위 규약을 잠근다). 겹침 테스트는 **겹침이 실제로 일어나는지 먼저 단언한다** — 안 그러면 두 그랩 영역이 떨어진 배치에서 순서 문제를 재지 못하고 공허하게 통과한다.

## 문서 접근성 요소 합성 (#79)

문서 본문이 CALayer 라 AX 트리가 없어, 두 뷰가 가시 (±2) 페이지의 텍스트를
합성 접근성 요소로 노출한다. 모델 (라벨·rect) 은 HwpKitCore 의
`HwpAccessibilityContent` 가 만들고 (`Sources/HwpKitCore/AGENTS.md`), 이
계층은 보관·수명·좌표 변환만 한다.

- **보관함 (`HwpDocumentAccessibilityStore`) 은 `#if` 밖 제네릭이다** — 요소
  타입만 플랫폼이 정하고 (`NSAccessibilityElement`/`UIAccessibilityElement`)
  수명 로직은 한 벌이라 macOS swift test 가 커버한다
  (`HwpSelectionHandleGeometry`·`fitZoomScale` 과 같은 틀).
- **수명은 레이어 가상화와 동기다.** `updateVisiblePages` 끝
  (오버레이 갱신 다음, 단위 캐시 축출 **앞**) 에서 `updateAccessibilityElements`
  가 실체화 페이지 밖 요소를 prune 하고 없는 페이지 몫을 만든다 — 축출 앞인
  것은 합성이 `HwpSelectionGeometry.units(forPage:)` 캐시를 읽기 때문이다.
  **문서 didSet 은 내용이 바뀌는 모든 분기 앞에서 store 를 전량 비운다**
  (프로그레시브·nil-token 동등 재전달·전체 교체) — stale 라벨의 1차 방어선이고,
  요소가 만들 때의 페이지 레이어 frame 을 anchor 로 기억해 frame 이 움직인
  페이지를 재생성하는 대조가 2차 방어선이다 (프로그레시브 로딩이 콘텐츠 폭을
  키우면 가운데 정렬 x 가 밀린다).
- **좌표 전략이 두 플랫폼에서 다르다.** macOS 는 요소가 콘텐츠 뷰 로컬 rect
  (`contentRect`) 만 저장하고 `accessibilityFrame()` 재정의가 **질의 시점**에
  `convert` + `convertToScreen` 으로 화면 좌표를 낸다 — 스크롤·magnification 이
  요소를 다시 만들지 않아도 항상 현재 값이다 (창이 없으면 .zero). iOS 는
  `accessibilityFrameInContainerSpace` (컨테이너 = `contentView`) 라 줌
  transform·스크롤 반영을 UIKit 이 질의 시점에 한다 — zoomScale 역보정 산식이
  없는 이유다.
- **낭독 순서는 store 평탄화가 정한다** (페이지 오름차순, 페이지 안은 모델
  순서: 상단 크롬 → 본문 → 하단 크롬 → 메모 패널). macOS 는
  `documentContentView.setAccessibilityChildren`, iOS 는
  `contentView.accessibilityElements` 에 매 갱신 대입한다 — 재생성이 없어도
  prune 만 돈 호출에서 목록이 줄어야 한다.
- **iOS 만 헤딩 트레이트가 있다** (`.header`, 개요 #77 제목 — VoiceOver 로터
  "제목" 탐색은 실체화된 가시 ±2 페이지 안에서만 동작한다). macOS 는
  staticText 로만 낸다 — AppKit 의 `NSAccessibilityHeadingRole` 은 macOS 26
  에야 생겨 (SDK 실측: `API_AVAILABLE(macos(26.0))`) 지원 하한 macOS 14+
  아래에서는 못 쓴다. 하한이 오르면 승격을 검토한다.
- 가드는 `HwpDocumentAccessibilityStoreTests` (수명·anchor·평탄화 순서 +
  `HwpDocumentAccessibility.units` 의 쪽별 제목 선별) 와 양 플랫폼
  `HwpDocument{NS,UI}ViewAccessibilityTests` (생성·좌표 합성·가상화 청소·교체
  무효화·메모 패널 오프셋, iOS 는 헤딩 트레이트까지). 화면 좌표 변환 자체와
  낭독 순서·로터는 자동화 밖이다 — macOS Accessibility Inspector / iOS
  시뮬레이터 VoiceOver 로 육안 확인한다.

## 레이어 가상화

- **visible ± 2 페이지만** sublayer 로 유지
- `updateVisiblePages(range:)` 가 diff 로 add/remove
- 스크롤/줌 시 자동 호출 (macOS: 클립 뷰 `boundsDidChangeNotification`, iOS: delegate)
- iOS: `UIScrollView.viewForZooming` = contentView (page layers 컨테이너)
- macOS: `NSScrollView.allowsMagnification` (0.25–5.0) 이 핀치 줌 담당 — `zoomScale` 은 magnification 을 읽고 쓰는 계산 프로퍼티 (별도 배율 상태 없음). 라이브 핀치 종료 (`didEndLiveMagnifyNotification`) 시에만 `contentsScale` 재적용
- macOS: `NSClickGestureRecognizer` 로 hit test (documentContentView 에 부착), iOS: `UITapGestureRecognizer`
- iOS 초기 위치: SwiftUI `makeUIView` 는 bounds 0 에서 document 를 대입하므로 센터링을 첫 non-zero `layoutSubviews` 로 **예약**한다. 그 창에 들어온 명시 페이지 요청(`scrollToPage`)은 인덱스를 함께 예약해 센터링 대신 그 페이지로 복원하고, 문서가 **전체 교체**되면 예약 인덱스를 버린다 (옛 문서 기준 페이지에서 열리는 것 방지). 같은 문서 재전달(`document == oldValue`)은 스크롤 유지가 의도라 예약도 보존
- 페이지 좌표 → 인덱스 변환은 macOS·iOS 모두 **이진 탐색** (`pageOriginsY` 오름차순). 선택 드래그·오토스크롤은 프레임마다 호출되므로 선형 스캔이면 만 쪽 문서에서 비용이 페이지 수에 비례한다

## fit 배율 (#78)

- **산식은 한 벌이다** — `HwpDocumentViewSupport.fitZoomScale(content:viewport:fit:range:)` 가 `#if` 밖 `nonisolated static` 으로 있고 두 뷰의 `applyFitZoom(_:)` 이 자기 캔버스·뷰포트를 넣어 부른다. `HwpSelectionHandleGeometry`·`effectiveContentsScale` 과 같은 틀이다: iOS 잡은 커버리지를 수집하지 않으므로 가드 안에만 사는 산식은 codecov patch 에 안 잡힌다.
- **뷰포트는 배율과 무관한 것을 재야 한다.** macOS 는 `NSScrollView.contentSize`(= 클립 뷰 **frame**), iOS 는 문서 뷰 **본체의 `bounds`** 다 (스크롤 뷰는 제약도 오토리사이즈 마스크도 없이 `layoutSubviews` 에서만 프레임을 받으므로, 크기가 바뀐 직후 레이아웃 전에는 그 프레임이 낡아 있다 — 본체 bounds 는 프레임 대입과 동시에 갱신되고 스크롤 뷰가 언제나 그것을 가득 채운다). macOS 확대는 클립 뷰 **bounds** 를 줄여 구현되므로 (`documentVisibleRect` 도 그것이다) 그쪽을 재면 맞춤을 누를 때마다 배율이 흘러간다 — 실측: magnification 1/2/0.5 에서 `contentView.frame` 은 800×600 불변이고 `bounds` 는 800/400/1600 으로 변한다. 가드는 `testFitZoomIsIndependentOfCurrentMagnification`(양 플랫폼).
- **기준은 쪽이 아니라 스크롤 캔버스다** (macOS `documentContentView.frame.width`, iOS `contentView.bounds.width`). 쪽은 캔버스 안에서 가운데 정렬되므로 현재 쪽 폭에 맞추면 더 넓은 구역이 하나라도 있을 때 가로 스크롤이 남는다. 캔버스 폭은 메모 패널을 이미 포함한다 (`rowWidth`).
- **595pt 하한이 플랫폼 비대칭을 만든다.** macOS 는 `rebuildPageOrigins`·`updateContentSize` 가 캔버스 폭에 `defaultPageSize.width` 하한을 두 겹으로 걸지만 iOS 에는 없다. 맞춤이 그 하한을 **그대로 물려받는** 것이 의도다 — 맞춤의 계약은 "가로 스크롤이 사라진다"이고 실제로 스크롤되는 것은 캔버스다. 대가로 폭 595pt 미만 문서에서 macOS 배율이 iOS 보다 작다.
- **높이는 현재 쪽의 `rowHeight`** (쪽 높이와 메모 패널 콘텐츠 높이의 max). 문서 전체 최댓값을 쓰면 거대한 쪽 하나가 1,030쪽 문서 전체를 읽을 수 없게 만든다.
- **쪽 맞춤은 스크롤까지가 계약이다** — 배율만 바꾸면 쪽 경계가 뷰포트 밖으로 밀려 "쪽 전체가 보인다"가 성립하지 않는다. 폭 맞춤은 반대로 스크롤을 **건드리지 않는다** (macOS 배율 setter 가 뷰포트 중심을 유지한다). 다만 호스트가 `currentPage` 를 함께 바인딩했으면 그 왕복이 쪽 머리로 되돌릴 수 있다 — 배율을 바꾸는 다른 경로(`-`/`+` 버튼)와 같은 성질이지 맞춤이 만든 것이 아니다.
- **캔버스는 프로그레시브 스냅샷마다 다시 선다** — 두 뷰의 `document` didSet 프로그레시브 분기가 `rebuildPageOrigins`·`updateContentSize` 를 다시 돌린다. 뒤에 오는 쪽이 더 넓으면(메모 패널 행은 쪽 폭의 1.312배) 캔버스가 커지므로 **로딩 중에 맞춘 결과는 잠정적**이고 가로 스크롤이 되살아날 수 있다. 자동 재적용을 넣지 않는 이유: 원샷 결정을 뒤집는 데다 "그 사이 사용자가 배율을 바꿨는가"를 `zoomScale` 바인딩 echo 와 구분할 수 없다 (`hwpZoomNeedsWriteback` 이 그 모호함을 덮으려고 있는 술어다). 다시 누르면 최종 폭에 맞는다.
- **예약은 문서 전체 교체에서 버리고, 문서가 아예 없던 상태에서 온 것만 살린다.** 남기면 문서 A 에서 건 맞춤이 나중에 B 의 배율을 뺏는다 (`pendingInitialPageIndex` 를 교체에서 버리는 R71 #2 와 같은 판단). 프로그레시브 스냅샷은 교체가 아니라 유지한다.
  - **조건은 `oldValue != nil` 이지 "쪽이 없었나" 가 아니다** (#107 리뷰). 한때 `oldValue?.pages.isEmpty == false` 였는데 그것은 `oldValue == nil`(진짜 "열자마자 맞춤")과 **0쪽 실제 문서**를 뭉갠다 — 후자에서 `true == false` 가 false 라 예약이 살아남아, A 에 건 `.page` 가 교체본 B 에 그대로 실렸다 (실측: 배율이 B 의 쪽 맞춤 0.3 으로, 스크롤도 B 의 쪽 머리로). **래퍼의 세대 가드(`fitToApply`)는 이것을 막지 못한다** — `configure` 에서 문서 대입이 fit 블록보다 **먼저**라 그 didSet 안에서 이미 적용된다. 두 층이 각자 막아야 한다. 프로그레시브를 조건에 넣을 필요는 없다: 그쪽은 위에서 조기 반환해 이 줄에 닿지 않는다. 가드는 양 플랫폼의 `testPendingFitFromAnEmptyDocumentIsDiscardedOnReplacement` 와 짝인 `testPendingFitFromNoDocumentStillAppliesToTheFirstDocument` — 후자가 없으면 예약을 통째로 버리는 구현도 통과한다. 그리고 교체 didSet 끝에서 `applyPendingFitZoom()` 을 **직접** 부른다 — 문서 대입은 자식 프레임만 바꿔 자기 자신에게 레이아웃을 걸지 않으므로, 안 부르면 "열자마자 맞춤"이 다음 리사이즈까지 잠든다.
- **그 직접 호출은 프로그레시브 분기에도 있어야 한다** (#78 리뷰). 그쪽도 지오메트리를 다시 세운 뒤 **조기 반환**하는데, `isProgressiveUpdate` 가 `pages.count >=` 라 **0쪽 → N쪽**이 그 경로로 온다 — 즉 쪽이 없어 예약된 요청이 깨어나야 할 자리가 정확히 거기다. 안 부르면 무관한 리사이즈까지 잠든다 (실측: 800×600 뷰에서 예약이 남고 배율 1.0 유지 → `layout()` 한 번에 1.3445 적용). **로더 경로로는 도달하지 않는다** — `HwpDocumentActor.buildDocument` 의 중간 스냅샷 방출이 `pages.append` **뒤**이고 `nextYieldCount = max(1, firstBatch)` 라 0쪽 중간 스냅샷이 없고, 0쪽 문서는 최종 스냅샷으로만 나와 같은 토큰 후속이 없다 (그 뒤 다른 문서는 토큰이 달라 교체 경로로 가 예약이 살아 적용된다). 그래서 호스트가 직접 구성한 문서에서만 나는 **잠재** 결함이지만 근거가 교체 경로와 한 글자도 다르지 않아, 한쪽만 두면 다음 사람이 그 비대칭을 의도로 읽는다. 예약된 `.page` 가 그 쪽 머리로 스크롤해 이 분기의 "스크롤 위치 유지"와 부딪히는 것은 의도다 — 예약이 있다는 것은 사용자가 건 명령이 아직 안 이뤄졌다는 뜻이다. 가드는 `testQueuedFitAppliesOnProgressiveSnapshotFromZeroPages`(양 플랫폼). 바로 위 `testPendingFitSurvivesProgressiveSnapshot` 은 **미실측 뷰**라 예약이 살아남는 것만 보므로 이 축을 대신하지 못한다.
- **쪽이 없는 문서에는 맞추지 않는다.** 0쪽에서도 캔버스에 `defaultPageSize` 하한이 서므로 가드가 없으면 산식이 "유령 A4" 배율을 성공으로 돌려주고, 원샷이라 진짜 문서가 도착해도 그대로 남는다.
- **예약 소비는 `applyPendingInitialCentering` 과 같은 노출을 진다** — 레이아웃 패스에서 `onZoomChanged` 가 발화해 호스트 바인딩이 그 자리에서 써진다. 새로 생긴 성질이 아니라 바로 옆 줄이 `onPageChanged` 로 이미 하고 있는 것과 같은 모양이다.
- **퇴화 입력은 산식이 nil 로 거른다.** 뷰포트가 아직 실측되지 않은 창(SwiftUI `makeUIView`/창에 붙기 전)이 이 경로로 오므로 뷰는 nil 을 "아직"으로 읽어 `pendingFitZoom` 에 예약하고 첫 실측 레이아웃에서 다시 시도한다 (iOS 초기 센터링 예약과 같은 형태, 적용 순서는 센터링 **다음**이어야 쪽 맞춤의 스크롤이 덮이지 않는다). 0 을 그대로 흘리면 하류가 못 잡는다 — `HwpZoomControls.sanitized` 는 0 을 finite 로 보아 하한 0.25 로 클램프하고, NaN 은 iOS 가 직전 값 유지·macOS 가 조용한 no-op 이라 원인이 어디에도 안 남는다.
- **가드 범위가 두 모드에서 다르다** — 폭 맞춤은 높이를 **읽지 않으므로** 높이가 퇴화(0·NaN·음수)해도 배율을 낸다. 산식을 정리하며 두 축 가드를 앞단 한 곳으로 모으면 이 비대칭이 사라져 폭 맞춤이 쪽 맞춤과 같은 조건에서만 성립하게 되므로, `testFitWidthIgnoresDegenerateHeight` 가 **같은 입력에 두 모드를 맞대어** 잠근다. 몫에도 별도 가드가 있다: 유한한 두 양수의 나눗셈도 거대 캔버스에서 **언더플로로 0** 이 되는데, 그 0 은 바로 아래 클램프가 하한 0.25 로 살려 내 "안내 없는 축소"가 된다 (`testFitZoomRejectsUnderflowedQuotient`).
- **배율 한계는 인자로 받는다** — `0.25...5.0` 은 이미 프로덕션 세 곳에 사본이 있어 산식이 네 번째를 만들면 안 된다. 호출부가 스크롤 뷰의 실제 한계를 정렬해 (`ClosedRange` 생성 트랩 방지) 넘긴다.
- **`HwpDocumentUIView` 본문에 새 저장 프로퍼티를 넣기 전에 lint 예산을 본다.** `type_body_length` error 임계가 400 이고 이 타입이 거기 붙어 있다 — `pendingFitZoom` 을 넣으며 `updateCenteringInset`·`trailingScrollExtent` 를 `HwpDocumentUIViewGeometry.swift` 확장으로 옮겨 본문을 **순감**시켰다 (399 → 385, 위 프로그레시브 호출을 더한 현재 390). #84 의 상태 묶기와 같은 처방이다.

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
- **`public extension` 안에 무수식자 멤버 두기** — 전부 public 이 된다. 뷰 확장을 파일로 쪼갤 때 뷰 본체에서 `private` 이던 가상화 세부(가시 범위·보존 창·페이지 프레임)가 그대로 공개 API 로 새어 나갔다 (#75 리뷰). 지오메트리 확장은 양 플랫폼 모두 **internal `extension`** 이고, 검색 확장처럼 일부만 공개해야 하는 파일은 멤버에 `internal` 을 명시한다 (`HwpDocumentUIViewSearch.swift` 가 그 예). SwiftFormat 의 `extensionAccessControl` 이 `on-extension` 이라 멤버가 전부 같은 수준이면 확장으로 올라가므로, internal 로 통일하면 형태가 유지된다

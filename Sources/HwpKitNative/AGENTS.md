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
├── Rendering/HwpImageStyleRenderer.swift # 표 107 crop/밝기/명암/효과 (CGImage.cropping + CoreImage)
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

## CRITICAL — macOS 좌표계 flip

`CALayer.draw(in:)` 는 **macOS 에서 기본 bottom-up (y+ 위) ctx, iOS 에서 top-down** 을 전달한다. 단, macOS 에서 조상 계층의 geometry flip 횟수가 홀수면 (isFlipped NSView 안 등) CA 가 이미 top-down 으로 보정한다.

`HwpPageLayer.draw(in:)` 은 `#if os(macOS)` 에서 **`contentsAreFlipped()` 가 false 일 때만** 수동으로 CTM 을 뒤집어 항상 top-down 을 보장한다. 레이어 자체에 `isGeometryFlipped = true` 를 켜면 안 된다 — flipped 조상 뷰와 합쳐져 **이중 flip (짝수) → 페이지가 상하 반전**된다 (실제로 겪은 버그).

macOS 페이지 레이어는 `HwpFlippedContentView` (isFlipped=true, NSScrollView documentView) 에 붙는다. NSClipView 는 documentView 의 flippedness 를 미러링하지만, `contentsAreFlipped()` 런타임 가드가 조상 flip 홀짝 변화를 동적으로 보정하므로 안전하다.

`drawText` 의 CT flip (`translateBy` + `scaleBy(x: 1, y: -1)`) 과 `drawFlippedImage` 는 top-down 정규화 이후를 전제로 하므로 그대로 유지.

## CRITICAL — contentsScale (Retina 선명도)

`CALayer.contentsScale` 기본값은 1.0 — 설정하지 않으면 Retina 에서 1x 래스터를 확대해 **글씨가 흐릿해진다** (실제로 겪은 버그). 두 뷰 모두 `effectiveContentsScale` (backing/screen scale × max(1, zoom), 상한 4× — 산식은 `HwpDocumentViewSupport.effectiveContentsScale`) 을 레이어 생성 시와 zoom/backing 변경 시 적용한다 (macOS: `viewDidChangeBackingProperties`, iOS: `didMoveToWindow` + `scrollViewDidEndZooming`). 일괄 갱신은 `HwpDocumentViewSupport.updateContentsScale` — 메모 패널 레이어도 페이지와 함께 재래스터한다 (macOS·iOS 통일됨).

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

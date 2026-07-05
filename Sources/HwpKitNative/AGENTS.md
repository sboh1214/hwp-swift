# HwpKitNative

플랫폼 브릿지 target (AppKit + UIKit). **SwiftUI import 금지.** HwpKit target 이 이 위에서 SwiftUI 래핑.

## 구조

```
HwpKitNative/
├── Platform/PlatformTypes.swift    # typealias (PlatformView/Color/Image/Font) — 뷰 chrome + provider가 사용
├── Rendering/HwpPageLayer.swift    # CALayer + paint list executor (Core Text, drawImageReference)
├── Rendering/HwpPageImageProvider.swift  # HwpImageStore + HwpImageCache + HwpImageAdapter 연결
├── macOS/HwpDocumentNSView.swift   # NSView + 레이어 가상화
├── iOS/HwpDocumentUIView.swift     # UIView + UIScrollView (pinch zoom 내장)
├── Cache/HwpImageCache.swift       # LRU actor (100MB cap) — 뷰가 provider에 주입
└── Concurrency/HwpDocumentActor.swift  # parse/layout dispatch actor
```

## 이미지 렌더 경로

1. paginator가 `.drawImageReference(binItemId:rect:)` 명령을 방출 (비트맵 없음)
2. 뷰가 document 변경 시 `HwpPageImageProvider(store: document.imageStore, cache: imageCache)` 생성해 레이어에 주입
3. `HwpPageLayer.draw` 가 `cachedImage` 동기 조회 → 없으면 로딩 표시 + `requestImage` (async 디코드: `HwpImageCache.fetch` → `HwpImageAdapter.decode`)
4. 디코드 완료 시 `onImageResolved` → main queue에서 레이어 `setNeedsDisplay`
5. 이미지는 flipped context 보정 (`drawFlippedImage`)으로 그린다 — 지우면 상하 반전

## CRITICAL — macOS 180° flip

`CALayer.draw(in:)` 는 **macOS 에서 bottom-up (y+ 위) ctx, iOS 에서 top-down (y+ 아래) ctx** 를 전달한다. 좌표계가 반대.

`HwpPageLayer.init` 에서 `#if os(macOS)` 조건으로 **`isGeometryFlipped = true`** 강제 → 양쪽 플랫폼이 동일하게 top-down 이 됨. 그 다음 `drawText` 의 CT flip 로직 (`ctx.translateBy` + `ctx.scaleBy(x: 1, y: -1)`) 이 일관되게 동작.

**이 flag 를 지우거나 조건을 반전하면 macOS 텍스트가 거꾸로 렌더된다.**

## HwpDocumentActor.buildDocument

- `HwpFile` (URL/Data) 을 background executor 에서 파싱
- `HwpIndex` + `HwpImageStore` + `HwpPaginator` 구축
- `page(at:)` 를 페이지 nil 이 나올 때까지 loop 하여 `HwpDocument.pages` 채움
- `await paginator.unsupportedElements()` 로 `HwpDocument.unsupportedElements` 채움 — 실제 `HwpUnsupportedDetector` walk (top-level + nested ctrls) 는 HwpKitCore 의 `HwpPaginator.collectUnsupported`/`walkUnsupported` 가 pagination 중 수행
- 반환된 `HwpDocument` 는 fully-paginated (View 는 lazy 재요청 안 함)

## 레이어 가상화

- **visible ± 2 페이지만** sublayer 로 유지
- `updateVisiblePages(range:)` 가 diff 로 add/remove
- 스크롤/줌 시 자동 호출
- iOS: `UIScrollView.viewForZooming` = contentView (page layers 컨테이너)
- macOS: `NSClickGestureRecognizer` 로 hit test, iOS: `UITapGestureRecognizer`

## Callback 발화 규약

| Callback | 발화 시점 |
|---|---|
| `onHyperlinkTapped(url)` | tap/click 이 `.hyperlink` 블록 프레임을 hit 했을 때 |
| `onPageChanged(page)` | `updateVisiblePages` 가 visible range 를 갱신할 때 |
| `onUnsupportedElement(element)` | 양쪽 플랫폼: document `didSet` 시 `unsupportedElements` 순회 (콜백은 document 할당보다 먼저 배선됨) |

## 안티 패턴

- 페이지 스크롤 시 새 페이지 fetch 를 main thread 에서 sync — 반드시 `HwpDocumentActor.page(at:)` async 호출
- 300 페이지 문서를 열 때 모든 페이지 layer 를 persistent 로 유지 — 메모리 폭발. `visible ± 2` 정책 유지
- Dark mode 에서 페이지 배경/텍스트 색을 반전 — HWP 저자 의도 그대로 렌더 (whitepaper metaphor)

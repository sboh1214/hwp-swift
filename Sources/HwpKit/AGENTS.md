# HwpKit

SwiftUI 공개 API target. HwpKitNative 위에 `NSViewRepresentable` / `UIViewRepresentable` 로 래핑. **AppKit/UIKit direct import 금지** (플랫폼 뷰는 HwpKitNative 통해).

## 공개 API 표면

- `HwpDocumentLoader.load(from:)` — URL / Data / FileWrapper 오버로드. 내부적으로 `HwpDocumentActor` 사용. 에러는 `HwpDocumentLoadError` 로 매핑
- `HwpDocumentView` — SwiftUI View. optional `zoomScale: Binding<CGFloat>?` + `currentPage: Binding<Int>?` + hyperlink/unsupported 콜백
- `HwpDocumentToolbar<Content>` — trailing content 를 받는 컨테이너 (툴바 chrome)
- `HwpPageNavigator(currentPage: Binding<Int>, totalPages: Int)` — "Page X of Y" + ± 버튼
- `HwpZoomControls(zoomScale: Binding<CGFloat>, range: ClosedRange<CGFloat>)` — 기본 range `0.25...5.0`

## 인덱싱 컨벤션

**`HwpPageNavigator` 는 1-indexed** (`currentPage ∈ 1...totalPages`). 하지만 native view (`HwpDocumentNSView` / `HwpDocumentUIView`) 는 0-indexed page range 를 사용.

`HwpDocumentView` 의 wrapper 가 변환:
- SwiftUI → native: `currentPage - 1`
- native → SwiftUI: `page + 1` (`handlePageChanged` 에서)

바인딩 테스트 (`HwpDocumentViewTests.testBindingsPropagateThroughNativeWrapper`) 는 이 오프셋 3 (= 2 + 1) 을 검증.

## Wrapper 재사용 규약

- `HwpDocumentView.updateNSView/UIView` 는 매번 `context.coordinator.update(...)` 로 콜백 참조를 갱신 (SwiftUI 가 뷰를 재사용해도 최신 클로저가 발화되도록)
- `Coordinator` 클래스가 hyperlink/unsupported/pageChanged 발화를 SwiftUI 쪽 콜백으로 프록시

## v1 스코프 밖 (추가 금지)

- File picker / document browser — 앱 책임
- 검색 / find — v1 OUT (텍스트 선택/복사/전체 선택은 구현됨 — HwpKitCore/Selection)
- 인쇄 / PDF export
- 편집 API (v2)
- 하이퍼링크 URL 라우팅 — 콜백만 제공, 실제 오픈은 앱 책임

## 안티 패턴

- `HwpDocumentView` 에서 `AppKit`/`UIKit` 을 직접 import — HwpKitNative 의 `Representable` wrapper 만 사용
- 툴바 컴포넌트에 `openURL` / `share` / `print` / `search` / `save` 관련 SwiftUI action 추가 — 스코프 크리프 (테스트로 grep 검증 있음)
- `HwpDocumentLoader` 결과를 SwiftUI `@State` 에 담아 재로드 시 clear 를 생략 — Sample 에서 `document = nil` 초기화 패턴 유지

## Sample 앱

`Sample/HwpSwiftSample.xcodeproj` 는 xcodegen 산출 (`Sample/project.yml` 이 spec). SwiftPM 로컬 참조 `packages.hwp-swift.path: ..` (repo 루트). 재생성: `cd Sample && xcodegen generate`.

Sandbox ON + `com.apple.security.files.user-selected.read-only` entitlement. 시뮬레이터 QA 는 `Documents/document.hwp` 자동 로드 (`.task` 훅).

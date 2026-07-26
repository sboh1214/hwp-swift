# HwpKit

SwiftUI 공개 API target. HwpKitNative 위에 `NSViewRepresentable` / `UIViewRepresentable` 로 래핑. **AppKit/UIKit direct import 금지** (플랫폼 뷰는 HwpKitNative 통해).

## 공개 API 표면

- `HwpDocumentLoader.load(from:)` — URL / Data / FileWrapper 오버로드. 내부적으로 `HwpDocumentActor` 사용. 에러는 `HwpDocumentLoadError` 로 매핑 (`CustomStringConvertible` + `LocalizedError` 채택 — 호스트가 `error.localizedDescription` 을 그대로 표시하면 감싼 파서/페이지네이터 원인이 나온다. 새 case 추가 시 `description` 도 함께 채울 것)
- `HwpDocumentLoader.loadUpdates(from:)` — 프로그레시브 로딩. `AsyncThrowingStream<HwpDocumentSnapshot, Error>` 로 첫 페이지 확정 즉시 스냅샷을 방출하고 배치 단위로 이어가다 최종 스냅샷(`isComplete`)으로 끝난다. 최종 문서는 `load(from:)` 결과와 동일. 뷰는 `HwpDocumentMetadata.loadToken` 으로 증분 적용(스크롤 유지) vs 전체 리셋을 판정
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

## 바인딩 방어 (public Binding 은 임의 값이 들어온다)

호스트 앱의 상태 복원/버그로 극단값이 들어와도 트랩하지 않아야 한다.

- 페이지: `hwpScrollPageIndex(fromOneBased:)` 가 **클램프를 뺄셈보다 먼저** 한다 (`max(1, page) - 1`). `page - 1` 을 먼저 하면 `Int.min` 에서 오버플로 트랩. macOS·iOS 분기가 이 헬퍼를 공유해 산식이 갈라지지 않는다
- 줌: `HwpZoomControls` 는 표시·쓰기 **양쪽**에서 `sanitized` 를 거친다 — 비-finite 는 1.0 폴백 후 range 클램프 (`Int(nan * 100)` 은 트랩, `min`/`max` 만으로는 NaN 이 통과)
- 줌 writeback 판정은 톨러런스 비교 **전에** 비-finite 를 처리한다 (`hwpZoomNeedsWriteback` / `hwpZoomBindingUnchanged`). NaN 은 abs 비교가 전부 false 라, 그냥 두면 핀치 echo·정규화가 모두 막혀 바인딩이 영구 NaN 으로 고착된다

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

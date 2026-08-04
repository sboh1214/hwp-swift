# HwpKit

SwiftUI 공개 API target. HwpKitNative 위에 `NSViewRepresentable` / `UIViewRepresentable` 로 래핑. **AppKit/UIKit direct import 금지** (플랫폼 뷰는 HwpKitNative 통해).

## 공개 API 표면

- `HwpDocumentLoader(fontResolver:)` — 렌더에 쓸 폰트 해석기 주입 (기본 `HwpFontResolver()`). 커밋된 기준선을 쓰는 렌더 가드가 전부 이 인자 하나에 기대 기기 독립을 얻는다 (`.testDeterministic` — 루트 AGENTS.md "렌더 가드 4층"). 호스트도 재현 가능한 조판이 필요하면 같은 방식으로 고정 resolver를 넘긴다
- `HwpDocumentLoader.load(from:)` — URL / Data / FileWrapper 오버로드. 내부적으로 `HwpDocumentActor` 사용. 에러는 `HwpDocumentLoadError` 로 매핑 (`CustomStringConvertible` + `LocalizedError` 채택 — 호스트가 `error.localizedDescription` 을 그대로 표시하면 감싼 파서/페이지네이터 원인이 나온다. 새 case 추가 시 `description` 도 함께 채울 것)
- `HwpDocumentLoader.loadUpdates(from:)` — 프로그레시브 로딩. `AsyncThrowingStream<HwpDocumentSnapshot, Error>` 로 첫 페이지 확정 즉시 스냅샷을 방출하고 배치 단위로 이어가다 최종 스냅샷(`isComplete`)으로 끝난다. 최종 문서는 `load(from:)` 결과와 동일. 뷰는 `HwpDocumentMetadata.loadToken` 으로 증분 적용(스크롤 유지) vs 전체 리셋을 판정
- `HwpDocumentView` — SwiftUI View. optional `zoomScale: Binding<CGFloat>?` + `currentPage: Binding<Int>?` + hyperlink/unsupported 콜백
- `HwpDocumentToolbar<Content>` — trailing content 를 받는 컨테이너 (툴바 chrome)
- `HwpPageNavigator(currentPage: Binding<Int>, totalPages: Int)` — "Page X of Y" + ± 버튼
- `HwpZoomControls(zoomScale: Binding<CGFloat>, range: ClosedRange<CGFloat>)` — 기본 range `0.25...5.0`
- `HwpPDFExporter` — `export(document:to:onProgress:)` / `exportData(document:onProgress:)` (둘 다 `async throws`). 화면과 **같은 paint list·같은 조판**으로 PDF를 만든다 (`HwpPageLayer.draw(in:)`가 뷰 계층 없이 임의 `CGContext`에 그리는 순수 오프스크린 렌더러라 가능하다 — 구현은 HwpKitNative의 `HwpPDFRenderer`). 페이지 단위 스트리밍이라 상주 메모리는 1페이지 몫이고, 페이지 경계마다 `Task.checkCancellation()` + `onProgress`(`HwpPDFExportProgress`) 발화. 에러는 `HwpPDFExportError`
  - **UI는 넘기지 않는다** — 저장 패널·공유 시트·인쇄 대화상자는 호스트 몫이다 (`Sample`이 `fileExporter` / `PDFDocument.printOperation` / `UIPrintInteractionController`로 배선하는 예를 보인다). 뷰를 직접 인쇄하는 경로는 없다: 레이어 가상화가 `visible ± 2`쪽만 들고 있어 인쇄 페이지네이션과 충돌한다

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
- 편집 API (v2)
- 하이퍼링크 URL 라우팅 — 콜백만 제공, 실제 오픈은 앱 책임
- 인쇄/공유 **UI** — PDF 바이트까지가 우리 몫 (`HwpPDFExporter`), 저장 패널·인쇄
  대화상자·공유 시트는 앱 책임. PDF 링크 애노테이션(`.hyperlink` paint 명령이
  rect+url을 들고 있어 가능은 하다)도 v1 밖

## 안티 패턴

- `HwpDocumentView` 에서 `AppKit`/`UIKit` 을 직접 import — HwpKitNative 의 `Representable` wrapper 만 사용
- HwpKit 안에서 `openURL` / `ShareLink` / `fileExporter` / `searchable` / `NSSavePanel` / `printOperation` 류의 **호스트 UI 액션**을 직접 호출 — 스코프 크리프. `Tests/HwpKitTests/HwpKitScopeGuardTests.swift`가 `Sources/HwpKit/**.swift`의 비-주석 줄을 스캔해 막는다 (#74에서 신설 — 그전까지 이 줄은 "테스트로 grep 검증 있음"이라 적고 있었지만 HwpKit 소스를 훑는 테스트는 없었다. `SourceSafetyTests`는 `Sources/CoreHwp`만 본다)
- `HwpDocumentLoader` 결과를 SwiftUI `@State` 에 담아 재로드 시 clear 를 생략 — Sample 에서 `document = nil` 초기화 패턴 유지

## Sample 앱

`Sample/HwpSwiftSample.xcodeproj` 는 xcodegen 산출 (`Sample/project.yml` 이 spec). SwiftPM 로컬 참조 `packages.hwp-swift.path: ..` (repo 루트). 재생성: `cd Sample && xcodegen generate`.

Sandbox ON + `com.apple.security.files.user-selected.read-write` entitlement — PDF 내보내기가 저장 패널로 고른 위치에 쓰므로 read-only로는 부족하다 (#74). 시뮬레이터 QA 는 `Documents/document.hwp` 자동 로드 (`.task` 훅).

내보내기는 **앱 임시 디렉터리에 먼저 쓰고** 그 파일을 `fileExporter`/인쇄로 넘긴다. 진행률·취소를 우리가 쥐어야 하고(1,030쪽이면 수 초), 사용자가 고른 위치에 직접 쓰면 취소 시 열리지 않는 부분 파일이 그 자리에 남기 때문이다. 저장 패널·인쇄는 진행 시트의 `onDismiss`에서 띄운다 — 두 모달을 같은 갱신 주기에 겹치면 두 번째 표시가 유실된다.

`#if os(macOS)` 분기가 여기서 처음 들어왔다: 인쇄 API(`PDFExportSupport.swift`)와 툴바 라벨이다. **iPhone 폭에는 컨트롤이 다 안 들어간다** — `HwpDocumentToolbar`가 그냥 `HStack`이라 넘치면 글자 단위로 줄바꿈해 "Zoom 100%"가 세 줄이 된다(시뮬레이터 실측, 내보내기 버튼 추가 전에도 두 줄이었다). 샘플은 iOS에서 버튼을 아이콘만으로 바꾸고 툴바를 가로 `ScrollView`에 넣어 해결한다 — **툴바 컴포넌트 자체를 고치지 않는다** (호스트 레이아웃은 호스트 몫).

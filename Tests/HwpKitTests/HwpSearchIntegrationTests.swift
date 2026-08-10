#if os(macOS)
    import AppKit
    import CoreGraphics
    import CoreText
    @testable import HwpKit
    import HwpKitCore
    import HwpKitNative
    import Nimble
    import SwiftUI
    import XCTest

    /// 검색(#75)의 SwiftUI 통합 — 실제 `NSHostingView`로 호스팅해 컨트롤러가
    /// 네이티브 뷰까지 도달하는지, 매치 점프가 페이지 바인딩과 수렴하는지 본다.
    @MainActor
    final class HwpSearchIntegrationTests: XCTestCase {
        private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        private static func document(pageTexts: [String]) -> HwpDocument {
            HwpDocument(
                pages: pageTexts.enumerated().map { index, text in
                    HwpPage(
                        size: CGSize(width: 595, height: 842),
                        margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                        blocks: [AnyHwpBlock(
                            frame: CGRect(x: 50, y: 100, width: 400, height: 20),
                            kind: .text,
                            attributedString: NSAttributedString(
                                string: text,
                                attributes: [
                                    kCTFontAttributeName as NSAttributedString.Key: Self.font,
                                ]
                            )
                        )],
                        pageNumber: index + 1
                    )
                },
                metadata: HwpDocumentMetadata(pageCount: pageTexts.count, loadToken: UUID()),
                unsupportedElements: []
            )
        }

        private static func host(
            _ view: HwpDocumentView
        ) -> (NSHostingView<HwpDocumentView>, HwpDocumentNSView)? {
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = CGRect(x: 0, y: 0, width: 480, height: 640)
            hostingView.layoutSubtreeIfNeeded()
            guard let native = hostingView.firstSearchSubview(of: HwpDocumentNSView.self) else {
                return nil
            }
            return (hostingView, native)
        }

        /// 호스트가 `@State`로 만든 컨트롤러가 그대로 네이티브 뷰에 도달해야
        /// 하이라이트가 붙는다.
        func testControllerReachesNativeViewThroughSwiftUI() async {
            let search = HwpSearchController()
            search.publishInterval = .zero
            let view = HwpDocumentView(
                document: Self.document(pageTexts: ["alpha beta"]),
                searchController: search
            )

            // 호스팅 뷰를 살려 둔다. 해체(`dismantleNSView`)가 세션을 떼므로
            // (#75 리뷰 — 그러지 않으면 컨트롤러가 문서 전체를 붙든다) 호스트를
            // 버린 채 네이티브 뷰만 들고 검색하는 것은 계약 밖이다.
            guard let (hostingView, native) = Self.host(view) else {
                fail("Expected HwpDocumentNSView in SwiftUI host")
                return
            }

            expect(native.searchController) === search
            search.search(text: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            // 지오메트리를 뷰의 선택 컨트롤러와 공유했다는 증거 — 공유가 안 됐으면
            // 컨트롤러에 문서가 없어 rect가 비어 있다. (레이어 부착 자체는
            // `HwpDocumentNSViewSearchTests`가 @testable로 따로 검증한다.)
            expect(search.highlightRects(forPage: 0)).toNot(beEmpty())
            withExtendedLifetime(hostingView) {}
        }

        /// 적대 시나리오 4 — 매치로 점프한 뒤 `currentPage` 바인딩 왕복이
        /// 스크롤을 원래 자리로 되튕기면 안 된다. 업데이트를 여러 번 태워
        /// 수렴을 확인한다.
        func testJumpingToMatchConvergesWithPageBindingWithoutBouncingBack() async {
            var currentPage = 1
            let search = HwpSearchController()
            search.publishInterval = .zero
            let view = HwpDocumentView(
                document: Self.document(
                    pageTexts: (0 ..< 8).map { $0 == 5 ? "needle here" : "filler \($0)" }
                ),
                currentPage: Binding(get: { currentPage }, set: { currentPage = $0 }),
                searchController: search
            )

            guard let (hostingView, native) = Self.host(view) else {
                fail("Expected HwpDocumentNSView in SwiftUI host")
                return
            }
            search.search(text: "needle")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))

            // 바인딩이 매치 페이지(1-기반 6)로 수렴한다
            await expect(currentPage).toEventually(equal(6), timeout: .seconds(2))

            // 이후 SwiftUI 업데이트를 여러 번 태워도 되튕기지 않는다
            for _ in 0 ..< 3 {
                hostingView.layoutSubtreeIfNeeded()
                hostingView.needsLayout = true
                hostingView.layoutSubtreeIfNeeded()
            }

            expect(native.currentVisiblePage()) == 5
            expect(currentPage) == 6
        }

        /// 적대 시나리오 6 — 같은 컨트롤러로 업데이트가 반복돼도 재스캔이
        /// 유발되지 않는다 (자기 급전 루프 가드).
        func testRepeatedSwiftUIUpdatesDoNotRestartTheScan() async {
            let search = HwpSearchController()
            search.publishInterval = .zero
            let view = HwpDocumentView(
                document: Self.document(pageTexts: ["alpha beta"]),
                searchController: search
            )
            guard let (hostingView, _) = Self.host(view) else {
                fail("Expected HwpDocumentNSView in SwiftUI host")
                return
            }
            search.search(text: "alpha")
            await expect(search.matchCount).toEventually(equal(1), timeout: .seconds(2))
            let revisionBefore = search.revision

            for _ in 0 ..< 5 {
                hostingView.needsLayout = true
                hostingView.layoutSubtreeIfNeeded()
            }

            expect(search.revision) == revisionBefore
            expect(search.matchCount) == 1
        }

        /// 검색을 넘기지 않은 기존 호출부는 그대로 동작한다 (소스 호환).
        func testOmittingSearchControllerLeavesNativeViewUnwired() {
            let view = HwpDocumentView(document: Self.document(pageTexts: ["alpha"]))

            guard let (_, native) = Self.host(view) else {
                fail("Expected HwpDocumentNSView in SwiftUI host")
                return
            }

            expect(native.searchController).to(beNil())
        }
    }

    private extension NSView {
        func firstSearchSubview<T: NSView>(of type: T.Type) -> T? {
            if let match = self as? T {
                return match
            }
            for subview in subviews {
                if let match = subview.firstSearchSubview(of: type) {
                    return match
                }
            }
            return nil
        }
    }
#endif

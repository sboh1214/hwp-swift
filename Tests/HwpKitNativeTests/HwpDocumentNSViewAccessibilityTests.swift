#if os(macOS)
    import AppKit
    import CoreText
    import Foundation

    // 단위 캐시 상한 단언이 `HwpSelectionGeometry.unitCache`(internal)를 읽는다.
    @testable import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import XCTest

    /// macOS 합성 AX 요소 (#79) — 가시 페이지 생성·가상화 동기 청소·문서 교체
    /// 무효화·좌표 합성. 화면 좌표 변환 (`accessibilityFrame`) 은 창이 있어야
    /// 성립하므로 여기서는 콘텐츠 뷰 로컬 rect (`contentRect`) 계약을 잠근다
    /// (창 없는 질의는 .zero — VoiceOver 는 창 밖 요소를 묻지 않는다).
    @MainActor
    final class HwpDocumentNSViewAccessibilityTests: XCTestCase {
        private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        private static func attributed(_ text: String) -> NSAttributedString {
            NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
        }

        private static func document(
            pageTexts: [String],
            chrome: String? = nil,
            memoText: String? = nil
        ) -> HwpDocument {
            HwpDocument(
                pages: pageTexts.enumerated().map { index, text in
                    var blocks = [AnyHwpBlock(
                        frame: CGRect(x: 50, y: 100, width: 400, height: 20),
                        kind: .text,
                        attributedString: attributed(text)
                    )]
                    if let chrome {
                        blocks.append(AnyHwpBlock(
                            frame: CGRect(x: 50, y: 20, width: 400, height: 16),
                            kind: .text,
                            attributedString: attributed(chrome),
                            role: .pageChrome
                        ))
                    }
                    return HwpPage(
                        size: CGSize(width: 595, height: 842),
                        margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                        blocks: blocks,
                        pageNumber: index + 1,
                        memoPanel: memoText.map {
                            HwpMemoPanel(
                                width: 200,
                                paintList: HwpPaintList(commands: [
                                    .drawText(
                                        attributedString: attributed($0),
                                        origin: CGPoint(x: 10, y: 20),
                                        lineWidth: 180
                                    ),
                                ])
                            )
                        }
                    )
                },
                metadata: HwpDocumentMetadata(pageCount: pageTexts.count),
                unsupportedElements: []
            )
        }

        private static func makeView(document: HwpDocument) -> HwpDocumentNSView {
            let view = HwpDocumentNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            view.document = document
            return view
        }

        private static func labels(of view: HwpDocumentNSView, page: Int) -> [String] {
            (view.accessibilityStore.elements(forPage: page) ?? [])
                .compactMap { $0.accessibilityValue() as? String }
        }

        // MARK: - 생성

        func testVisiblePagesExposeSynthesizedElements() {
            let view = Self.makeView(document: Self.document(pageTexts: ["본문 문단"]))

            expect(Self.labels(of: view, page: 0)) == ["본문 문단"]
            let children = view.documentContentView.accessibilityChildren()
            expect(children?.count) == 1
            expect(view.documentContentView.accessibilityRole()) == NSAccessibility.Role.group
        }

        /// 요소 rect 는 페이지 로컬 rect + 페이지 레이어 frame origin — 콘텐츠
        /// 뷰가 flipped 라 top-down 좌표를 그대로 쓴다.
        func testElementRectFollowsPageLayerOrigin() throws {
            let view = Self.makeView(document: Self.document(pageTexts: ["a", "b"]))
            view.updateVisiblePages(range: 1 ..< 2)

            let pageFrame = try XCTUnwrap(view.pageLayers[1]).frame
            let element = try XCTUnwrap(view.accessibilityStore.elements(forPage: 1)?.first)
            expect(element.contentRect) == CGRect(x: 50, y: 100, width: 400, height: 20)
                .offsetBy(dx: pageFrame.minX, dy: pageFrame.minY)
        }

        /// 창이 없으면 화면 좌표를 낼 수 없다 — .zero 로 답하고 트랩하지 않는다.
        func testAccessibilityFrameIsZeroWithoutWindow() throws {
            let view = Self.makeView(document: Self.document(pageTexts: ["본문"]))

            let element = try XCTUnwrap(view.accessibilityStore.elements(forPage: 0)?.first)
            expect(element.accessibilityFrame()) == .zero
        }

        // MARK: - 크롬·메모 패널

        func testChromeUnitsAreExposedBeforeBody() {
            let view = Self.makeView(
                document: Self.document(pageTexts: ["본문"], chrome: "머리말")
            )

            expect(Self.labels(of: view, page: 0)) == ["머리말", "본문"]
        }

        func testMemoPanelUnitsAreOffsetByPanelFrame() throws {
            let view = Self.makeView(
                document: Self.document(pageTexts: ["본문"], memoText: "메모 내용")
            )

            let panelFrame = try XCTUnwrap(view.memoPanelLayers[0]).frame
            let elements = try XCTUnwrap(view.accessibilityStore.elements(forPage: 0))
            expect(elements.count) == 2
            let memoElement = elements[1]
            expect(memoElement.accessibilityValue() as? String) == "메모 내용"
            // 패널 로컬 x=10 이 패널 frame (페이지 오른쪽 바깥) 으로 옮겨진다.
            expect(memoElement.contentRect.minX) == panelFrame.minX + 10
            expect(memoElement.contentRect.minY) >= panelFrame.minY
        }

        // MARK: - 가상화 동기 청소

        func testEvictedPagesDropTheirElements() {
            let view = Self.makeView(
                document: Self.document(pageTexts: (1 ... 10).map { "쪽 \($0)" })
            )

            view.updateVisiblePages(range: 5 ..< 6)

            expect(view.accessibilityStore.pageIndices.sorted()) == [3, 4, 5, 6, 7]
            expect(Self.labels(of: view, page: 5)) == ["쪽 6"]
        }

        /// AX 합성이 채운 단위 캐시는 유지 창으로 상한된다 — 축출 훅은 검색이
        /// 소유하므로 (#75) 검색이 없으면 AX 갱신이 직접 자른다. 안 자르면
        /// 스크롤만으로 1,030쪽 문서의 단위 전개 전량이 상주한다.
        func testUnitCacheIsBoundedToRetainedWindowWithoutSearch() throws {
            let view = Self.makeView(
                document: Self.document(pageTexts: (1 ... 10).map { "쪽 \($0)" })
            )

            view.updateVisiblePages(range: 5 ..< 6)

            let geometry = try XCTUnwrap(view.selectionController.geometry)
            expect(geometry.unitCache.keys.sorted()) == [3, 4, 5, 6, 7]
        }

        // MARK: - 문서 교체 무효화

        func testDocumentSwapDoesNotLeaveStaleElements() {
            let view = Self.makeView(document: Self.document(pageTexts: ["alpha"]))
            expect(Self.labels(of: view, page: 0)) == ["alpha"]

            view.document = Self.document(pageTexts: ["beta"])

            expect(Self.labels(of: view, page: 0)) == ["beta"]
            let labels = (view.documentContentView.accessibilityChildren() ?? [])
                .compactMap { child in
                    (child as? HwpTextAccessibilityElement)?.accessibilityValue() as? String
                }
            expect(labels) == ["beta"]
        }

        /// 스크롤된 상태의 교체 — updateContentSize의 frame 축소가 클립 뷰
        /// 클램프 → bounds 통지로 updateVisiblePages를 **동기 재진입**시키는데,
        /// 그 시점 선택 지오메트리가 아직 옛 문서면 새 페이지 frame을 anchor로
        /// 옛 문서 라벨이 store에 굳는다 (교체 didSet의 selectionController
        /// 대입이 지오메트리 재구성보다 앞이어야 하는 이유).
        func testDocumentSwapWhileScrolledDoesNotKeepOldLabels() {
            let view = Self.makeView(
                document: Self.document(pageTexts: (1 ... 10).map { "A쪽 \($0)" })
            )
            view.scrollToPage(at: 8)

            view.document = Self.document(pageTexts: ["B쪽 1"])

            expect(Self.labels(of: view, page: 0)) == ["B쪽 1"]
        }

        func testClearingDocumentClearsElements() {
            let view = Self.makeView(document: Self.document(pageTexts: ["alpha"]))

            view.document = nil

            expect(view.accessibilityStore.pageIndices).to(beEmpty())
            expect(view.documentContentView.accessibilityChildren()?.isEmpty ?? true) == true
        }
    }
#endif

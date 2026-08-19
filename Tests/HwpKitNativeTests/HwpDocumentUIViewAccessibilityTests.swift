#if os(iOS)
    import CoreGraphics
    import CoreText
    import Foundation
    import HwpKitCore
    @testable import HwpKitNative
    import Nimble
    import UIKit
    import XCTest

    /// iOS 합성 AX 요소 (#79) — macOS 대응 스위트와 같은 계약을 건다. 프레임은
    /// `accessibilityFrameInContainerSpace` (컨테이너 = contentView) 라 스크롤·
    /// 줌 변환을 UIKit 이 질의 시점에 반영한다.
    @MainActor
    final class HwpDocumentUIViewAccessibilityTests: XCTestCase {
        private static let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        private static func attributed(_ text: String) -> NSAttributedString {
            NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
        }

        private static func document(
            pageTexts: [String],
            memoText: String? = nil,
            outline: [HwpOutlineItem] = []
        ) -> HwpDocument {
            HwpDocument(
                pages: pageTexts.enumerated().map { index, text in
                    HwpPage(
                        size: CGSize(width: 595, height: 842),
                        margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                        blocks: [AnyHwpBlock(
                            frame: CGRect(x: 50, y: 100, width: 400, height: 20),
                            kind: .text,
                            attributedString: attributed(text)
                        )],
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
                metadata: HwpDocumentMetadata(pageCount: pageTexts.count, outline: outline),
                unsupportedElements: []
            )
        }

        private static func makeView(document: HwpDocument) -> HwpDocumentUIView {
            let view = HwpDocumentUIView(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
            view.layoutIfNeeded()
            view.document = document
            view.layoutIfNeeded()
            return view
        }

        private static func labels(of view: HwpDocumentUIView, page: Int) -> [String] {
            (view.accessibilityStore.elements(forPage: page) ?? [])
                .compactMap(\.accessibilityLabel)
        }

        // MARK: - 생성

        func testVisiblePagesExposeSynthesizedElements() {
            let view = Self.makeView(document: Self.document(pageTexts: ["본문 문단"]))

            expect(Self.labels(of: view, page: 0)) == ["본문 문단"]
            expect((view.contentView.accessibilityElements ?? []).count) == 1
        }

        /// 요소 프레임은 페이지 로컬 rect + 페이지 레이어 frame origin 을 컨테이너
        /// (contentView) 좌표에 둔다 — 줌 배율 역보정 산식이 없는 이유다.
        func testElementFrameFollowsPageLayerOriginInContainerSpace() throws {
            let view = Self.makeView(document: Self.document(pageTexts: ["a", "b"]))
            view.updateVisiblePages(range: 1 ..< 2)

            let pageFrame = try XCTUnwrap(view.pageLayers[1]).frame
            let element = try XCTUnwrap(view.accessibilityStore.elements(forPage: 1)?.first)
            expect(element.accessibilityFrameInContainerSpace)
                == CGRect(x: 50, y: 100, width: 400, height: 20)
                .offsetBy(dx: pageFrame.minX, dy: pageFrame.minY)
            expect(element.accessibilityContainer) === view.contentView
        }

        // MARK: - 헤딩 트레이트 (#77 로터 재료)

        func testOutlineHeadingGetsHeaderTrait() throws {
            let heading = HwpOutlineItem(
                kind: .heading, title: "제1장 총칙", level: 1, pageNumber: 1, ordinal: 0
            )
            let view = Self.makeView(
                document: Self.document(pageTexts: ["제1장 총칙"], outline: [heading])
            )

            let element = try XCTUnwrap(view.accessibilityStore.elements(forPage: 0)?.first)
            expect(element.accessibilityTraits.contains(.header)) == true

            let plain = Self.makeView(document: Self.document(pageTexts: ["일반 본문"]))
            let plainElement = try XCTUnwrap(plain.accessibilityStore.elements(forPage: 0)?.first)
            expect(plainElement.accessibilityTraits.contains(.header)) == false
            expect(plainElement.accessibilityTraits.contains(.staticText)) == true
        }

        // MARK: - 메모 패널

        func testMemoPanelUnitsAreOffsetByPanelFrame() throws {
            let view = Self.makeView(
                document: Self.document(pageTexts: ["본문"], memoText: "메모 내용")
            )

            let panelFrame = try XCTUnwrap(view.memoPanelLayers[0]).frame
            let elements = try XCTUnwrap(view.accessibilityStore.elements(forPage: 0))
            expect(elements.count) == 2
            expect(elements[1].accessibilityLabel) == "메모 내용"
            expect(elements[1].accessibilityFrameInContainerSpace.minX) == panelFrame.minX + 10
        }

        // MARK: - 가상화 동기 청소

        func testEvictedPagesDropTheirElements() {
            let view = Self.makeView(
                document: Self.document(pageTexts: (1 ... 10).map { "쪽 \($0)" })
            )

            view.updateVisiblePages(range: 5 ..< 6)

            // iOS 유지 창은 가시 ±2 를 페이지 수로 클램프한 범위다.
            expect(view.accessibilityStore.pageIndices.sorted()) == [3, 4, 5, 6, 7]
            expect(Self.labels(of: view, page: 5)) == ["쪽 6"]
        }

        // MARK: - 문서 교체 무효화

        func testDocumentSwapDoesNotLeaveStaleElements() {
            let view = Self.makeView(document: Self.document(pageTexts: ["alpha"]))
            expect(Self.labels(of: view, page: 0)) == ["alpha"]

            view.document = Self.document(pageTexts: ["beta"])
            view.layoutIfNeeded()

            expect(Self.labels(of: view, page: 0)) == ["beta"]
            let exposed = (view.contentView.accessibilityElements ?? [])
                .compactMap { ($0 as? UIAccessibilityElement)?.accessibilityLabel }
            expect(exposed) == ["beta"]
        }

        /// 스크롤된 상태의 교체 — applyPendingInitialCentering의 setContentOffset이
        /// scrollViewDidScroll → updateVisiblePages를 **동기 재진입**시키는데,
        /// 그 시점 선택 지오메트리가 아직 옛 문서면 새 페이지 frame을 anchor로
        /// 옛 문서 라벨이 store에 굳어 VoiceOver가 이전 문서를 읽는다 (교체
        /// didSet의 selectionController 대입이 지오메트리 재구성보다 앞이어야
        /// 하는 이유).
        func testDocumentSwapWhileScrolledDoesNotKeepOldLabels() {
            let view = Self.makeView(
                document: Self.document(pageTexts: (1 ... 10).map { "A쪽 \($0)" })
            )
            view.scrollToPage(at: 8)
            view.layoutIfNeeded()

            view.document = Self.document(pageTexts: ["B쪽 1"])
            view.layoutIfNeeded()

            expect(Self.labels(of: view, page: 0)) == ["B쪽 1"]
        }

        func testClearingDocumentClearsElements() {
            let view = Self.makeView(document: Self.document(pageTexts: ["alpha"]))

            view.document = nil
            view.layoutIfNeeded()

            expect(view.accessibilityStore.pageIndices).to(beEmpty())
            expect((view.contentView.accessibilityElements ?? []).isEmpty) == true
        }
    }
#endif

import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 글자처럼 취급 개체의 바깥 여백 (#193) — 줄은 개체 + 바깥 여백의 **바깥 상자**를 한
    /// 글자로 예약하고, 개체는 그 안에서 왼쪽·위쪽 여백만큼 들어가 놓인다.
    ///
    /// 기대값은 한컴오피스 한글 12.30 (macOS) 실측(2026-09-18)이다: 30pt 표에 바깥 여백
    /// 왼 10·오 5·위 7·아래 3pt를 주면 줄 캐시 `vertsize`가 40pt, 표 상단이 줄 상단 + 7pt,
    /// 표 왼쪽이 앞 글자 끝 + 10pt, 뒤 글자가 여백 없는 줄보다 15pt 오른쪽이고 줄 글자의
    /// 베이스라인은 줄 상단 + 0.85 × 40이다. 종전에는 여백을 예약도 배치도 하지 않았다.
    final class HwpInlineObjectMarginTests: XCTestCase {
        private typealias Support = FloatingTablePrecedesTextSupport

        func testOuterMarginsReadTheTable70Order() {
            var property = CoreHwp.HwpCommonCtrlProperty(commonCtrlId: .table)
            property.marginArray = [1000, 500, 700, 300]
            let margins = HwpObjectAnchorGeometry.OuterMargins(property)
            expect(margins.left).to(beCloseTo(10, within: 0.001))
            expect(margins.right).to(beCloseTo(5, within: 0.001))
            expect(margins.top).to(beCloseTo(7, within: 0.001))
            expect(margins.bottom).to(beCloseTo(3, within: 0.001))
            expect(margins.horizontal).to(beCloseTo(15, within: 0.001))
            expect(margins.vertical).to(beCloseTo(10, within: 0.001))

            // 음수 여백은 0, 넷이 아닌 배열·속성 없음은 여백 없음이다.
            property.marginArray = [-200, 0, 0, 0]
            expect(HwpObjectAnchorGeometry.OuterMargins(property).left) == 0
            property.marginArray = [100, 100]
            expect(HwpObjectAnchorGeometry.OuterMargins(property)) == .zero
            expect(HwpObjectAnchorGeometry.OuterMargins(nil)) == .zero
        }

        func testInlineObjectOriginIsInsetByLeftAndTopMargins() {
            let origin = HwpObjectAnchorGeometry.inlineObjectOrigin(
                outerBoxOrigin: CGPoint(x: 100, y: 200),
                margins: .init(left: 10, right: 5, top: 7, bottom: 3)
            )
            expect(origin) == CGPoint(x: 110, y: 207)
        }

        /// 줄 예약은 바깥 상자다 — 30 × 10pt 개체 + 여백 15 × 10pt.
        func testReservationIsTheOuterBox() throws {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "가", suffix: "나")
            var object = HwpSynthetic.inlineShapeObject(width: 3000, height: 1000)
            object.commonCtrlProperty.marginArray = [1000, 500, 700, 300]
            paragraph.ctrlHeaderArray = [.genShapeObject(object)]
            let built = HwpTextRunBuilder(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
            ).build(paragraph: paragraph)
            let marker = try XCTUnwrap(Self.markerRange(in: built))
            let line = CTLineCreateWithAttributedString(built.attributedSubstring(from: marker))
            var ascent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, nil, nil)
            expect(CGFloat(width)).to(beCloseTo(45, within: 0.01))
            expect(ascent).to(beCloseTo(20, within: 0.01))
        }

        /// 단 폭에 딸린 예약 폭을 다른 단으로 다시 풀어도 좌우 여백은 그대로 더해진다 (#164의
        /// 다시 풀기 경로 — 개체 폭만 다시 풀고 여백을 빠뜨리면 조각에서만 예약이 좁아진다).
        func testColumnRelativeReservationKeepsItsMarginsWhenRescaled() {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "가", suffix: "나")
            var object = HwpSynthetic.columnRelativeInlineObject(
                widthPercent: 5000, heightPercent: 100
            )
            object.commonCtrlProperty.marginArray = [1000, 500, 0, 0]
            paragraph.ctrlHeaderArray = [.genShapeObject(object)]
            let built = HwpTextRunBuilder(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic,
                sizeResolver: Self.resolver(columnWidth: 100),
                attributeCache: nil
            ).build(paragraph: paragraph)
            expect(Self.reservedWidth(in: built)).to(beCloseTo(50 + 15, within: 0.01))
            let rescaled = HwpInlineObjectReservation.rescaledForColumn(
                built, resolver: Self.resolver(columnWidth: 200)
            )
            expect(Self.reservedWidth(in: rescaled)).to(beCloseTo(100 + 15, within: 0.01))
        }

        /// 페이지 경로: 글자처럼 취급 표가 줄 상단 + 위 여백, 줄 시작 + 왼쪽 여백에 놓이고,
        /// 줄 상자는 표 + 위·아래 여백(40pt)이라 같은 줄 글자의 베이스라인이 그 0.85배다.
        func testInlineTableSitsInsideItsOuterBox() async throws {
            var host = try Support.host(
                rowCount: 1, margins: [1000, 500, 700, 300], treatAsChar: true
            )
            // 실물처럼 공통 속성에 절대 크기(200 × 30pt)를 싣는다 — 줄 예약의 근거다.
            guard case var .table(inlineTable) = host.ctrlHeaderArray?.first else {
                XCTFail("expected an inline table")
                return
            }
            inlineTable.commonCtrlProperty.width = 20000
            inlineTable.commonCtrlProperty.height = 3000
            inlineTable.commonCtrlProperty.propertyInfo.widthRelativeToRawValue = 4
            inlineTable.commonCtrlProperty.propertyInfo.widthRelativeTo = .absolute
            inlineTable.commonCtrlProperty.propertyInfo.heightRelativeToRawValue = 2
            inlineTable.commonCtrlProperty.propertyInfo.heightRelativeTo = .absolute
            host.ctrlHeaderArray = [.table(inlineTable)]
            let paginator = Support.paginator(bodyParagraphs: [host])
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)
            let body = page.blocks.filter { $0.role == .body }
            let table = try XCTUnwrap(body.first { $0.kind == .table })
            let hostBlock = try XCTUnwrap(body.last {
                $0.kind == .text && ($0.attributedString?.string.contains("table anchor") ?? false)
            })
            expect(table.frame.minY).to(beCloseTo(hostBlock.frame.minY + 7, within: 0.01))
            expect(table.frame.minX).to(beCloseTo(hostBlock.frame.minX + 10, within: 0.01))
            expect(table.frame.height).to(beCloseTo(30, within: 0.01))

            let attributed = try XCTUnwrap(hostBlock.attributedString)
            let line = try XCTUnwrap(HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: hostBlock.frame.origin,
                lineWidth: hostBlock.frame.width
            ).first)
            expect(line.baselineOrigin.y).to(beCloseTo(hostBlock.frame.minY + 34, within: 0.01))
            // 뒤 글자는 바깥 상자 뒤 — 줄 시작 + 10 + 200 + 5.
            let suffix = (attributed.string as NSString).range(of: "table anchor").location
            let suffixX = CTLineGetOffsetForStringIndex(line.line, suffix, nil)
            expect(line.baselineOrigin.x + suffixX)
                .to(beCloseTo(hostBlock.frame.minX + 215, within: 0.01))
        }

        /// 표가 아닌 개체(도형·그림)의 페이지 경로 — 줄 시작의 개체가 왼쪽·위쪽 여백만큼 들어가고,
        /// 단 폭 개체는 블록 **폭을 그대로** 지킨다 (PR 리뷰: 폭 클램프를 개체 원점으로 재면
        /// 왼쪽 여백만큼 좁아져 그림 비트맵이 눌렸다 — 클램프 기준은 바깥 상자 원점이다).
        func testInlineObjectIsInsetAndKeepsItsWidth() async throws {
            let probe = try await Self.pictureBlock(width: 10000, margins: [0, 0, 0, 0])
            let inset = try await Self.pictureBlock(width: 10000, margins: [1000, 500, 700, 300])
            expect(inset.picture.minX).to(beCloseTo(probe.picture.minX + 10, within: 0.01))
            expect(inset.picture.minY).to(beCloseTo(inset.host.minY + 7, within: 0.01))
            expect(inset.picture.width).to(beCloseTo(100, within: 0.01))

            let columnWide = try await Self.pictureBlock(
                width: UInt32((probe.host.width * 100).rounded()), margins: [1000, 0, 0, 0]
            )
            expect(columnWide.picture.minX).to(beCloseTo(columnWide.host.minX + 10, within: 0.01))
            expect(columnWide.picture.width).to(beCloseTo(probe.host.width, within: 0.01))
        }

        /// 줄이 자리를 예약하지 않은 개체(한 축 0 — 예약 생략)는 바깥 상자가 없어 들이지 않는다
        /// (PR 리뷰: 들이면 예약 없는 개체만 베이스라인 아래·뒤 글자 위로 옮겨졌다).
        func testUnreservedInlineObjectIsNotInset() async throws {
            let plain = try await Self.shapeBlock(height: 0, margins: [0, 0, 0, 0])
            let margined = try await Self.shapeBlock(height: 0, margins: [1000, 500, 700, 300])
            expect(margined.minX).to(beCloseTo(plain.minX, within: 0.01))
            expect(margined.minY).to(beCloseTo(plain.minY, within: 0.01))
        }

        /// 컨테이너 경로 — 표 셀 문단의 글자처럼 취급 그림도 바깥 여백만큼 들어간다
        /// (`HwpParagraphObjectCollector.origin`, 페이지 경로와 같은 산식).
        func testCellInlinePictureIsInsetByItsMargins() throws {
            func pictureRect(margins: [CoreHwp.HWPUNIT16]) throws -> CGRect {
                var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "나")
                var picture = HwpSynthetic.inlinePictureObject(
                    width: 3000, height: 2000, binItemId: 1
                )
                picture.commonCtrlProperty.marginArray = margins
                paragraph.ctrlHeaderArray = [.genShapeObject(picture)]
                let table = HwpSynthetic.table(
                    cellWidth: 20000, rowHeights: [6000], property: 0,
                    cellParagraphs: [[[paragraph]]]
                )
                let result = HwpTableLayout(fontResolver: .testDeterministic).layout(
                    table: table, availableWidth: 400, index: HwpIndex(from: CoreHwp.HwpFile())
                )
                guard case let .success(frame) = result else { throw LayoutFailure() }
                return try XCTUnwrap(frame.rows[0].cells[0].images.first?.rect)
            }
            let plain = try pictureRect(margins: [0, 0, 0, 0])
            let margined = try pictureRect(margins: [1000, 500, 700, 300])
            expect(margined.minX).to(beCloseTo(plain.minX + 10, within: 0.01))
            expect(margined.minY).to(beCloseTo(plain.minY + 7, within: 0.01))
            expect(margined.width).to(beCloseTo(30, within: 0.01))
        }

        private struct LayoutFailure: Error {}

        /// 줄 시작에 글자처럼 취급 개체 하나를 둔 문단 — (개체 블록, 문단 블록) 프레임.
        private static func pictureBlock(
            width: UInt32, margins: [CoreHwp.HWPUNIT16]
        ) async throws -> (picture: CGRect, host: CGRect) {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "", suffix: "")
            var object = HwpSynthetic.inlineShapeObject(width: width, height: 2000)
            object.commonCtrlProperty.marginArray = margins
            paragraph.ctrlHeaderArray = [.genShapeObject(object)]
            let blocks = try await body(of: [paragraph])
            let placed = try XCTUnwrap(blocks.first { $0.kind != .text })
            let host = try XCTUnwrap(blocks.last { $0.kind == .text })
            return (placed.frame, host.frame)
        }

        /// '가[개체]나' 문단의 도형 블록 프레임 (폭 30pt, 높이 `height` HWPUNIT).
        private static func shapeBlock(
            height: UInt32, margins: [CoreHwp.HWPUNIT16]
        ) async throws -> CGRect {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "가", suffix: "나")
            var object = HwpSynthetic.inlineShapeObject(width: 3000, height: height)
            object.commonCtrlProperty.marginArray = margins
            paragraph.ctrlHeaderArray = [.genShapeObject(object)]
            let blocks = try await body(of: [paragraph])
            return try XCTUnwrap(blocks.first { $0.kind != .text }?.frame)
        }

        private static func body(
            of paragraphs: [CoreHwp.HwpParagraph]
        ) async throws -> [AnyHwpBlock] {
            let paginator = Support.paginator(bodyParagraphs: paragraphs)
            let rendered = try await paginator.page(at: 0)
            return try XCTUnwrap(rendered).blocks.filter { $0.role == .body }
        }

        private static func resolver(columnWidth: CGFloat) -> HwpObjectSizeResolver {
            HwpObjectSizeResolver(
                paperSize: CGSize(width: 595, height: 842),
                contentSize: CGSize(width: 425, height: 700),
                columnWidth: columnWidth
            )
        }

        private static func markerRange(in string: NSAttributedString) -> NSRange? {
            var found: NSRange?
            string.enumerateAttribute(
                HwpAttributedStringKey.controlIndex,
                in: NSRange(location: 0, length: string.length)
            ) { value, range, stop in
                guard (value as? NSNumber)?.intValue == 0 else { return }
                found = range
                stop.pointee = true
            }
            return found
        }

        private static func reservedWidth(in string: NSAttributedString) -> CGFloat? {
            markerRange(in: string).map {
                CGFloat(CTLineGetTypographicBounds(
                    CTLineCreateWithAttributedString(string.attributedSubstring(from: $0)),
                    nil, nil, nil
                ))
            }
        }
    }
#endif

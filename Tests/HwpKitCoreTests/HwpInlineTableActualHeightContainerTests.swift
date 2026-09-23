import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 글자처럼 취급 표의 실제 높이 예약 (#214) — 조판기 입력·예약 다시 잡기·각주·비등폭 단.
    /// 본문 흐름은 `HwpInlineTableActualHeightTests`.
    final class HwpInlineTableActualHeightContainerTests: XCTestCase {
        private typealias Support = InlineTableActualHeightSupport

        private static let index = HwpIndex(from: CoreHwp.HwpFile())

        /// 마커 하나의 예약 — run delegate의 폭·ascent와 마커에 실린 예약 높이 속성.
        private struct Reservation {
            let width: CGFloat
            let ascent: CGFloat
            let attribute: CGFloat?
        }

        /// 조판 문자열에서 `controlIndex` 마커가 예약한 자리.
        private static func reservation(
            in string: NSAttributedString, controlIndex: Int
        ) -> Reservation? {
            var found: Reservation?
            string.enumerateAttribute(
                HwpAttributedStringKey.controlIndex,
                in: NSRange(location: 0, length: string.length)
            ) { value, range, stop in
                guard (value as? NSNumber)?.intValue == controlIndex else { return }
                let line = CTLineCreateWithAttributedString(string.attributedSubstring(from: range))
                var ascent: CGFloat = 0
                let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))
                let attribute = (string.attribute(
                    HwpAttributedStringKey.inlineObjectHeight, at: range.location,
                    effectiveRange: nil
                ) as? NSNumber).map { CGFloat($0.doubleValue) }
                found = Reservation(width: width, ascent: ascent, attribute: attribute)
                stop.pointee = true
            }
            return found
        }

        /// 넘긴 높이가 표의 저작 높이를 대신한다 — 폭과 바깥 여백은 그대로이고, 표가 아닌 개체는
        /// 목록에 있어도 저작 높이를 쓴다. 넘기지 않으면 종전대로 저작 높이다.
        func testReservationUsesTheSuppliedTableHeight() throws {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "가", suffix: "나")
            paragraph.paraText?.charArray.insert(CoreHwp.HwpChar(type: .extended, value: 11), at: 2)
            paragraph.ctrlHeaderArray = [
                .table(try Support.staleTable(
                    rows: 4, instanceId: 1, margins: [283, 283, 283, 283]
                )),
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 3000, height: 1000)),
            ]
            var builder = HwpTextRunBuilder(index: Self.index, fontResolver: .testDeterministic)
            let authored = builder.build(paragraph: paragraph)
            builder.inlineTableHeights = [0: 40, 1: 99]
            let laidOut = builder.build(paragraph: paragraph)

            let before = try XCTUnwrap(Self.reservation(in: authored, controlIndex: 0))
            expect(before.ascent).to(beCloseTo(11.28 + 5.66, within: 0.01))
            let after = try XCTUnwrap(Self.reservation(in: laidOut, controlIndex: 0))
            expect(after.ascent).to(beCloseTo(40 + 5.66, within: 0.01))
            expect(after.attribute).to(beCloseTo(40 + 5.66, within: 0.01))
            expect(after.width).to(beCloseTo(before.width, within: 0.001))
            // 도형은 표가 아니다 — 목록의 99를 쓰지 않는다.
            let shape = try XCTUnwrap(Self.reservation(in: laidOut, controlIndex: 1))
            expect(shape.ascent).to(beCloseTo(10, within: 0.01))
        }

        /// 예약 다시 잡기는 목록에 든 **예약 있는** 마커만 바꾸고 폭을 지킨다 — 바꿀 것이 없으면
        /// 원본 그대로다 (사본을 뜨지 않는다).
        func testReservedHeightRewriteTouchesOnlyListedMarkers() throws {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "가", suffix: "나")
            paragraph.paraText?.charArray.insert(CoreHwp.HwpChar(type: .extended, value: 11), at: 2)
            paragraph.ctrlHeaderArray = [
                .table(try Support.staleTable(rows: 1, instanceId: 1)),
                .table(try Support.staleTable(rows: 2, instanceId: 2)),
            ]
            let built = HwpTextRunBuilder(index: Self.index, fontResolver: .testDeterministic)
                .build(paragraph: paragraph)
            let width = try XCTUnwrap(Self.reservation(in: built, controlIndex: 1)).width

            let rewritten = HwpInlineObjectReservation.withReservedHeights(
                built, outerHeights: [1: 30]
            )
            let first = try XCTUnwrap(Self.reservation(in: rewritten, controlIndex: 0))
            let second = try XCTUnwrap(Self.reservation(in: rewritten, controlIndex: 1))
            expect(first.ascent).to(beCloseTo(2.82, within: 0.01))
            expect(second.ascent).to(beCloseTo(30, within: 0.01))
            expect(second.attribute).to(beCloseTo(30, within: 0.01))
            expect(second.width).to(beCloseTo(width, within: 0.001))
            expect(HwpInlineObjectReservation.reservedMarkerControlIndices(in: built)) == [0, 1]

            let empty = HwpInlineObjectReservation.withReservedHeights(built, outerHeights: [:])
            expect(empty) === built
            let unchanged = HwpInlineObjectReservation.withReservedHeights(
                built, outerHeights: [0: 2.82]
            )
            expect(unchanged) === built
        }

        /// 각주 안 표도 그려지는 높이로 줄을 잡는다 — 각주 글줄의 베이스라인이 표 아래(0.85 × 30)에
        /// 오고 표는 줄 상자 안에 든다. 저작 8.46pt로 잡으면 글줄이 표 위쪽(8.5)에 겹쳐 그려졌다.
        func testFootnoteLineReservesTheLaidOutTableHeight() throws {
            let note = Support.host(
                table: try Support.staleTable(rows: 3, instanceId: 3, width: 10000), suffix: " 각주 뒤"
            )
            let geometry = HwpPageGeometry(
                pageSize: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
                contentFrame: CGRect(x: 72, y: 72, width: 451, height: 698),
                headerFrame: nil,
                footerFrame: nil,
                columnFrames: [CGRect(x: 72, y: 72, width: 451, height: 698)]
            )
            let blocks = HwpFootnoteLayout(fontResolver: .testDeterministic).layout(
                footnotes: [.init(paragraph: note, number: 1)], onPage: geometry, index: Self.index
            )
            let block = try XCTUnwrap(blocks.first)
            let table = try XCTUnwrap(block.nestedTables.first)
            let paragraph = try XCTUnwrap(block.paragraphs.first)
            let line = try XCTUnwrap(HwpDrawnTextLayout.lines(
                attributedString: paragraph.attributedString,
                origin: paragraph.rect.origin, lineWidth: paragraph.rect.width
            ).first)
            expect(table.rect.height).to(beCloseTo(30, within: 0.01))
            expect(line.baselineOrigin.y - paragraph.rect.minY).to(beCloseTo(25.5, within: 0.01))
            expect(table.rect.minY).to(beCloseTo(paragraph.rect.minY, within: 0.01))
            expect(block.frame.height).to(beGreaterThanOrEqualTo(30 - 0.01))
        }

        /// 각주 문단의 줄 캐시가 표보다 짧으면(저작 뒤 셀 내용이 커진 문서) 문단 높이는 캐시를 따르지만
        /// 각주 블록은 표를 담는다 — 줄 예약이 그려지는 높이라 예약 상자로는 하한이 안 걸리므로 문단
        /// rect를 넘친 만큼 하한을 둔다 (#214 리뷰). 없으면 표와 글줄이 다음 각주 위로 흘러나간다.
        func testStaleFootnoteLineCacheStillContainsTheTable() throws {
            var note = Support.host(
                table: try Support.staleTable(rows: 3, instanceId: 4, width: 10000), suffix: " 각주 뒤"
            )
            note.paraLineSeg = try HwpSynthetic.lineSegParagraph(
                "캐시", segments: [(location: 0, height: 1000)]
            ).paraLineSeg
            let geometry = HwpPageGeometry(
                pageSize: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
                contentFrame: CGRect(x: 72, y: 72, width: 451, height: 698),
                headerFrame: nil,
                footerFrame: nil,
                columnFrames: [CGRect(x: 72, y: 72, width: 451, height: 698)]
            )
            let blocks = HwpFootnoteLayout(fontResolver: .testDeterministic).layout(
                footnotes: [.init(paragraph: note, number: 1)], onPage: geometry, index: Self.index
            )
            let block = try XCTUnwrap(blocks.first)
            let table = try XCTUnwrap(block.nestedTables.first)
            expect(table.rect.height).to(beCloseTo(30, within: 0.01))
            expect(block.frame.height).to(beGreaterThanOrEqualTo(table.rect.maxY - 0.01))

            // 캐시 줄 상자(28)가 표(30)보다 짧고 줄 간격까지 더한 전진량(34)보다는 짧지 않은 경우 —
            // 각주 끝 블록은 줄 간격을 빼고 쌓으므로 하한은 줄 상자 아래 기준이어야 한다 (2차 리뷰).
            note.paraLineSeg = try HwpSynthetic.lineSegParagraph(
                "캐시", segments: [(location: 0, height: 2800)]
            ).paraLineSeg
            let tight = try XCTUnwrap(HwpFootnoteLayout(fontResolver: .testDeterministic).layout(
                footnotes: [.init(paragraph: note, number: 1)], onPage: geometry, index: Self.index
            ).first)
            let tightTable = try XCTUnwrap(tight.nestedTables.first)
            expect(tight.frame.height).to(beGreaterThanOrEqualTo(tightTable.rect.maxY - 0.01))
        }

        /// 비등폭 단 — 줄을 잰 좁은 단에서는 표가 단 폭으로 잘려 셀 글이 두 줄(20pt)이지만, 표가
        /// 놓이는 넓은 단에서는 한 줄(10pt)이다. 예약도 놓이는 단의 높이로 다시 잡혀 마커가 10pt를
        /// 예약한다 — 잰 단의 20pt가 남으면 줄이 표보다 10pt 크다.
        func testColumnOfDifferentWidthReReservesTheTableHeight() async throws {
            let prefix = (0 ..< 14).map { "word\($0)" }.joined(separator: " ") + " "
            let suffix = (14 ..< 18).map { "word\($0)" }.joined(separator: " ")
            let text = prefix + "X" + suffix
            let streamCount = UInt32(prefix.utf16.count + 8 + suffix.utf16.count)
            let boundary = streamCount / 3
            var paragraph = try HwpSynthetic.columnCacheParagraph(text, segments: [
                .init(textIndex: 0, location: 0, height: 1500, width: 13416),
                .init(textIndex: boundary / 2, location: 2552, height: 1500, width: 13416),
                .init(textIndex: boundary, location: 0, height: 1500, width: 26837),
                .init(textIndex: boundary + 20, location: 2552, height: 1500, width: 26837),
            ], charCount: streamCount)
            paragraph.paraText = HwpSynthetic.paragraphWithInlineControl(
                prefix: prefix, suffix: suffix
            ).paraText
            // 250pt 표 — 좁은 단(134pt)에서는 단 폭으로 잘려 30자 셀 글이 두 줄이 된다.
            let table = try Support.staleTable(
                rows: 1, instanceId: 6, width: 25000,
                cellText: { _ in "abcdefghij abcdefghij abcdefgh" }
            )
            paragraph.ctrlHeaderArray = [
                .table(table),
                .column(HwpSynthetic.column(count: 2, widths: [10339, 20682], gaps: [1747, 0])),
            ]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section], index: Self.index, fontResolver: .testDeterministic
            )
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)
            let columns = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("word") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(columns.count) == 2
            guard columns.count == 2 else { return }
            let placed = try XCTUnwrap(Support.table(on: page, instanceId: 6))
            expect(placed.frame.height).to(beCloseTo(10, within: 0.01))
            let attributed = try XCTUnwrap(columns[1].attributedString)
            let marker = (attributed.string as NSString).range(of: "\u{FFFC}").location
            let reserved = try XCTUnwrap(attributed.attribute(
                HwpAttributedStringKey.inlineObjectHeight, at: marker, effectiveRange: nil
            ) as? NSNumber)
            expect(CGFloat(reserved.doubleValue)).to(beCloseTo(10, within: 0.01))
            // 그려지는 줄의 run delegate도 같은 예약이다 (CT 줄 ascent = 예약 높이).
            let line = try XCTUnwrap(HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: columns[1].frame.origin,
                lineWidth: columns[1].frame.width
            ).first { NSLocationInRange(marker, $0.stringRange) })
            expect(line.ascent).to(beCloseTo(10, within: 0.01))
        }
    }
#endif

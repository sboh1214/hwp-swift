import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 줄 앵커의 **예약 치수**와 개체의 실제 조판 크기가 갈릴 때의 컨테이너 높이
    /// 하한 (R65). 예약은 저작 치수(표 69)에서 오고 표·글상자의 실제 높이는
    /// 내용이 정하므로, 예약이 0보다 크다는 것만으로 "줄이 담았다"고 접으면 안 된다.
    final class HwpInlineReservationTests: XCTestCase {
        /// 예약보다 크게 조판된 개체의 초과분은 줄이 담지 않는다 — 하한을 안 올리면
        /// 컨테이너가 짧은 채로 남아 개체가 다음 각주·행 위로 흘러나간다.
        func testObjectTallerThanReservationRaisesFloor() throws {
            let collected = try collect(reservedAscent: 10)

            expect(collected.shapes.count) == 1
            let bottom = try XCTUnwrap(collected.shapes.first).rect.maxY
            expect(bottom).to(beCloseTo(300, within: 0.5))
            expect(collected.floatingBottom).to(beCloseTo(bottom, within: 0.5))
        }

        /// 반대 가드: 줄이 개체를 다 담았으면 하한을 얹지 않는다. 얹으면 라인 캐시를
        /// 신뢰하는 규약이 깨져 셀이 저작 높이보다 부풀고 페이지 분할이 한글과
        /// 어긋난다 (#91의 반대 방향, `testInlineObjectInCellKeepsAuthoredRowHeight`).
        func testObjectInsideReservationKeepsNoFloor() throws {
            let collected = try collect(reservedAscent: 400)
            expect(collected.floatingBottom).to(beNil())
        }

        /// 300pt 개체 하나를 `reservedAscent`만큼만 예약한 줄에 앵커로 단다.
        private func collect(
            reservedAscent: CGFloat
        ) throws -> HwpParagraphObjectCollector.Objects {
            var paragraph = try HwpSynthetic.cachedInlineControlParagraph(
                segments: [(location: 0, height: 1000)]
            )
            paragraph.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 5000, height: 30000)),
            ]
            let frame = HwpParagraphFrame(
                totalHeight: reservedAscent,
                lines: [HwpLineFrame(
                    origin: .zero,
                    width: 200,
                    baseline: reservedAscent,
                    attributedRange: NSRange(location: 0, length: 1),
                    inlineAnchors: [HwpInlineAnchor(
                        controlIndex: 0, xOffset: 0, ascent: reservedAscent, width: 50
                    )]
                )]
            )
            let collector = HwpParagraphObjectCollector(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic,
                sizeResolver: nil,
                collectsTextboxes: true,
                attributeCache: nil,
                collectsTables: true
            )
            return collector.objects(
                in: paragraph,
                frame: frame,
                paragraphRect: CGRect(x: 0, y: 0, width: 200, height: reservedAscent)
            )
        }
    }
#endif

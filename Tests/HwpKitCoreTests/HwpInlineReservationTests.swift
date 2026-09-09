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

        /// 단 기준 상대 크기 개체의 예약 폭은 목적 단 기하로 다시 풀린다 — 절대 크기
        /// 개체는 그대로다 (`HwpInlineObjectReservation.rescaledForColumn`, #164 리뷰).
        func testColumnRelativeReservationRescalesToDestinationColumn() {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "가", suffix: "나")
            paragraph.paraText?.charArray.append(CoreHwp.HwpChar(type: .extended, value: 11))
            paragraph.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.columnRelativeInlineObject(
                    widthPercent: 5000, heightPercent: 100
                )),
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 3000, height: 1000)),
            ]
            let built = HwpTextRunBuilder(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic,
                sizeResolver: Self.resolver(columnWidth: 100),
                attributeCache: nil
            ).build(paragraph: paragraph)
            expect(Self.reservedWidth(of: built, controlIndex: 0)).to(beCloseTo(50, within: 0.01))

            let rescaled = HwpInlineObjectReservation.rescaledForColumn(
                built, resolver: Self.resolver(columnWidth: 200)
            )
            expect(Self.reservedWidth(of: rescaled, controlIndex: 0))
                .to(beCloseTo(100, within: 0.01))
            // 절대 크기 개체(3000 HWPUNIT = 30pt)는 단 폭과 무관하다.
            expect(Self.reservedWidth(of: rescaled, controlIndex: 1))
                .to(beCloseTo(30, within: 0.01))
            // 예약 높이는 폭과 달리 '단' 기준이 없어 그대로다 (표 70).
            expect(Self.reservedAscent(of: rescaled, controlIndex: 0))
                .to(beCloseTo(Self.reservedAscent(of: built, controlIndex: 0) ?? -1, within: 0.01))
        }

        /// **잇달아 있는** 마커도 개체마다 자기 치수를 지킨다 — `enumerateAttribute`가 크기
        /// 기준이 같은 이웃 마커를 한 범위로 합치므로, 범위 첫 마커의 치수를 통째로 얹으면
        /// 뒤 개체의 예약 폭·높이가 덮인다 (PR 리뷰).
        func testAdjacentColumnRelativeReservationsKeepTheirOwnSize() {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "가", suffix: "나")
            // 가 + 마커 + 마커 + 나 — 두 마커가 인접한 run이 된다.
            paragraph.paraText?.charArray.insert(
                CoreHwp.HwpChar(type: .extended, value: 11), at: 1
            )
            paragraph.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.columnRelativeInlineObject(
                    widthPercent: 5000, heightPercent: 100
                )),
                .genShapeObject(HwpSynthetic.columnRelativeInlineObject(
                    widthPercent: 7500, heightPercent: 300
                )),
            ]
            let built = HwpTextRunBuilder(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic,
                sizeResolver: Self.resolver(columnWidth: 100),
                attributeCache: nil
            ).build(paragraph: paragraph)
            // 두 마커가 실제로 이웃해 있어야 병합 조건을 태운다 (표식이 갈리면 무의미해진다).
            expect(built.string).to(contain("\u{FFFC}\u{FFFC}"))
            expect(Self.reservedWidth(of: built, controlIndex: 0)).to(beCloseTo(50, within: 0.01))
            expect(Self.reservedWidth(of: built, controlIndex: 1)).to(beCloseTo(75, within: 0.01))

            let rescaled = HwpInlineObjectReservation.rescaledForColumn(
                built, resolver: Self.resolver(columnWidth: 200)
            )
            expect(Self.reservedWidth(of: rescaled, controlIndex: 0))
                .to(beCloseTo(100, within: 0.01))
            // 앞 마커의 100pt로 덮이지 않는다 — 자기 기준(75%)으로 풀린 150pt다.
            expect(Self.reservedWidth(of: rescaled, controlIndex: 1))
                .to(beCloseTo(150, within: 0.01))
            // 예약 높이도 마커마다 그대로다 (쪽 기준 1%·3% = 7pt·21pt).
            expect(Self.reservedAscent(of: rescaled, controlIndex: 0))
                .to(beCloseTo(7, within: 0.01))
            expect(Self.reservedAscent(of: rescaled, controlIndex: 1))
                .to(beCloseTo(21, within: 0.01))
        }

        /// 다시 풀 마커가 없으면 사본을 뜨지 않는다 — 조각마다 문자열을 복사하지 않는다.
        func testReservationRescaleKeepsStringWhenNothingIsColumnRelative() {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "가", suffix: "나")
            paragraph.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 3000, height: 1000)),
            ]
            let built = HwpTextRunBuilder(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic,
                sizeResolver: Self.resolver(columnWidth: 100),
                attributeCache: nil
            ).build(paragraph: paragraph)
            expect(HwpInlineObjectReservation.rescaledForColumn(
                built, resolver: Self.resolver(columnWidth: 200)
            )) === built
        }

        private static func resolver(columnWidth: CGFloat) -> HwpObjectSizeResolver {
            HwpObjectSizeResolver(
                paperSize: CGSize(width: 595, height: 842),
                contentSize: CGSize(width: 425, height: 700),
                columnWidth: columnWidth
            )
        }

        /// controlIndex 마커가 줄에서 차지하는 폭 (run delegate 예약).
        private static func reservedWidth(
            of attributedString: NSAttributedString,
            controlIndex: Int
        ) -> CGFloat? {
            marker(of: attributedString, controlIndex: controlIndex).map {
                CGFloat(CTLineGetTypographicBounds(
                    CTLineCreateWithAttributedString(
                        attributedString.attributedSubstring(from: $0)
                    ),
                    nil, nil, nil
                ))
            }
        }

        private static func reservedAscent(
            of attributedString: NSAttributedString,
            controlIndex: Int
        ) -> CGFloat? {
            guard let range = marker(of: attributedString, controlIndex: controlIndex)
            else { return nil }
            var ascent: CGFloat = 0
            _ = CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(
                    attributedString.attributedSubstring(from: range)
                ),
                &ascent, nil, nil
            )
            return ascent
        }

        private static func marker(
            of attributedString: NSAttributedString,
            controlIndex: Int
        ) -> NSRange? {
            var found: NSRange?
            attributedString.enumerateAttribute(
                HwpAttributedStringKey.controlIndex,
                in: NSRange(location: 0, length: attributedString.length)
            ) { value, range, stop in
                guard (value as? NSNumber)?.intValue == controlIndex else { return }
                found = range
                stop.pointee = true
            }
            return found
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

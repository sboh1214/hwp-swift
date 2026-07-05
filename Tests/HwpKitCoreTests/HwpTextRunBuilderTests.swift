@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpTextRunBuilderTests: XCTestCase {
        func testEmptyParagraphReturnsEmptyAttributedString() throws {
            let paragraph = paragraph(text: "", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            expect(result.length) == 0
        }

        func testSingleShapeParagraphProducesOneFontRange() throws {
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)

            let ranges = fontRanges(in: result)
            expect(result.string) == "hello"
            expect(ranges.count) == 1
            expect(ranges.first?.range) == NSRange(location: 0, length: 5)
            expect(ranges.first?.font).notTo(beNil())
        }

        func testMixedKoreanAndEnglishChunksOnScriptSwitch() throws {
            let paragraph = paragraph(text: "안녕hello", runs: [(0, 0)])
            let shape = try charShape(faceScaleX: [100, 110, 100, 100, 100, 100, 100])
            let result = builder(shapes: [0: shape])
                .build(paragraph: paragraph)
            let rangeCount = fontRanges(in: result).count

            expect(rangeCount) >= 2
        }

        func testBoldFlagProducesBoldCTFontTrait() throws {
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape(property: 0b10)])
                .build(paragraph: paragraph)
            let font = fontRanges(in: result).first?.font

            expect(font).notTo(beNil())
            expect(font.map { CTFontGetSymbolicTraits($0).contains(.traitBold) }) == true
        }

        func testUnderlineFlagAddsSingleUnderlineStyle() throws {
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape(property: 0b100)])
                .build(paragraph: paragraph)
            let value = result.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? NSNumber

            expect(value?.intValue) == NSUnderlineStyle.single.rawValue
        }

        func testInlineObjectMarkerCarriesControlIndexAndRunDelegate() {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "AB", suffix: "C")
            paragraph.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 5000, height: 3000)),
            ]
            let result = builder(shapes: [:]).build(paragraph: paragraph)

            expect(result.string) == "AB\u{FFFC}C"
            let markerAttributes = result.attributes(at: 2, effectiveRange: nil)
            let controlIndex = markerAttributes[HwpAttributedStringKey.controlIndex] as? NSNumber
            expect(controlIndex?.intValue) == 0
            expect(
                markerAttributes[kCTRunDelegateAttributeName as NSAttributedString.Key]
            ).toNot(beNil())
            // 일반 문자에는 컨트롤 attribute가 없다.
            let charAttributes = result.attributes(at: 0, effectiveRange: nil)
            expect(charAttributes[HwpAttributedStringKey.controlIndex]).to(beNil())
        }

        func testNonObjectExtendedControlReservesNoWidth() {
            // 구역/단/머리말 정의 마커는 한글과 같이 폭 0 (글리프 공간 없음).
            var host = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = "AB".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                + [CoreHwp.HwpChar(type: .extended, value: 16)]
            host.paraText = paraText
            host.ctrlHeaderArray = [.header(HwpSynthetic.listControl(
                ctrlId: .header,
                paragraphs: []
            ))]
            let withMarker = builder(shapes: [:]).build(paragraph: host)
            expect(withMarker.string) == "AB\u{FFFC}"
            let controlIndex = withMarker.attributes(at: 2, effectiveRange: nil)[
                HwpAttributedStringKey.controlIndex
            ] as? NSNumber
            expect(controlIndex?.intValue) == 0

            let plain = builder(shapes: [:])
                .build(paragraph: paragraph(text: "AB", runs: [(0, 0)]))
            let markerLine = HwpParagraphLayout().layout(
                attributedString: withMarker,
                paraShape: CoreHwp.HwpParaShape(),
                columnWidth: 400
            ).lines.first
            let plainLine = HwpParagraphLayout().layout(
                attributedString: plain,
                paraShape: CoreHwp.HwpParaShape(),
                columnWidth: 400
            ).lines.first
            expect(markerLine?.width).to(beCloseTo(plainLine?.width ?? -1, within: 0.01))
        }

        func testConsecutiveExtendedControlsCountOrdinalsInOrder() {
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [
                CoreHwp.HwpChar(type: .extended, value: 2),
                CoreHwp.HwpChar(type: .extended, value: 11),
            ]
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [
                .section(CoreHwp.HwpSectionDef()),
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 5000, height: 3000)),
            ]
            let result = builder(shapes: [:]).build(paragraph: paragraph)

            expect(result.string) == "\u{FFFC}\u{FFFC}"
            let first = result.attributes(at: 0, effectiveRange: nil)
            let second = result.attributes(at: 1, effectiveRange: nil)
            expect((first[HwpAttributedStringKey.controlIndex] as? NSNumber)?.intValue) == 0
            expect((second[HwpAttributedStringKey.controlIndex] as? NSNumber)?.intValue) == 1
            // 개체 마커는 개체 크기(50pt)를, 비개체 마커는 폭 0을 예약한다.
            let lines = HwpParagraphLayout().layout(
                attributedString: result,
                paraShape: CoreHwp.HwpParaShape(),
                columnWidth: 400
            ).lines
            expect(lines.first?.width).to(beCloseTo(50, within: 0.01))
            expect(lines.first?.baseline).to(beCloseTo(30, within: 0.01))
        }
    }

    private extension HwpTextRunBuilderTests {
        func builder(shapes: [UInt32: CoreHwp.HwpCharShape]) -> HwpTextRunBuilder {
            HwpTextRunBuilder(index: index(shapes: shapes), fontResolver: .testDeterministic)
        }

        func index(shapes: [UInt32: CoreHwp.HwpCharShape]) -> HwpIndex {
            HwpIndex(
                charShapes: shapes,
                paraShapes: [:],
                borderFills: [:],
                tabDefs: [:],
                styles: [:],
                bullets: [:],
                numberings: [:],
                binData: [:],
                faceNamesKorean: [:],
                faceNamesEnglish: [:],
                faceNamesChinese: [:],
                faceNamesJapanese: [:],
                faceNamesEtc: [:],
                faceNamesSymbol: [:],
                faceNamesUser: [:]
            )
        }

        func paragraph(text: String, runs: [(UInt32, UInt32)]) -> CoreHwp.HwpParagraph {
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = text.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
            paragraph.paraText = paraText

            var paraCharShape = CoreHwp.HwpParaCharShape()
            paraCharShape.startingIndex = runs.map(\.0)
            paraCharShape.shapeId = runs.map(\.1)
            paragraph.paraCharShape = paraCharShape
            return paragraph
        }

        func charShape(
            property: UInt32 = 0,
            faceScaleX: [UInt8] = [100, 100, 100, 100, 100, 100, 100]
        ) throws -> CoreHwp.HwpCharShape {
            var data = Data()
            append(UInt16(0), count: 7, to: &data)
            data.append(contentsOf: faceScaleX)
            data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0].map { UInt8(bitPattern: Int8($0)) })
            data.append(contentsOf: [100, 100, 100, 100, 100, 100, 100])
            data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0].map { UInt8(bitPattern: Int8($0)) })
            append(Int32(1200), to: &data)
            append(property, to: &data)
            data.append(UInt8(bitPattern: Int8(0)))
            data.append(UInt8(bitPattern: Int8(0)))
            append(UInt32(0), count: 4, to: &data)
            return try CoreHwp.HwpCharShape.load(data, CoreHwp.HwpVersion(5, 0, 1, 0))
        }

        func fontRanges(in string: NSAttributedString) -> [(range: NSRange, font: CTFont?)] {
            var ranges: [(NSRange, CTFont?)] = []
            string.enumerateAttribute(
                kCTFontAttributeName as NSAttributedString.Key,
                in: NSRange(location: 0, length: string.length)
            ) { value, range, _ in
                // swiftlint:disable:next force_cast
                ranges.append((range, value.map { $0 as! CTFont }))
            }
            return ranges
        }

        func append(_ value: some FixedWidthInteger, count: Int, to data: inout Data) {
            for _ in 0 ..< count {
                append(value, to: &data)
            }
        }

        func append(_ value: some FixedWidthInteger, to data: inout Data) {
            var littleEndian = value.littleEndian
            data.append(withUnsafeBytes(of: &littleEndian) { Data($0) })
        }
    }
#endif

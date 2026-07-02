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
            let result = builder(shapes: [0: try charShape(faceScaleX: [100, 110, 100, 100, 100, 100, 100])])
                .build(paragraph: paragraph)
            let rangeCount = fontRanges(in: result).count

            expect(rangeCount) >= 2
        }

        func testBoldFlagProducesBoldCTFontTrait() throws {
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape(property: 0b10)]).build(paragraph: paragraph)
            let font = fontRanges(in: result).first?.font

            expect(font).notTo(beNil())
            expect(font.map { CTFontGetSymbolicTraits($0).contains(.traitBold) }) == true
        }

        func testUnderlineFlagAddsSingleUnderlineStyle() throws {
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape(property: 0b100)]).build(paragraph: paragraph)
            let value = result.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? NSNumber

            expect(value?.intValue) == NSUnderlineStyle.single.rawValue
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
                ranges.append((range, value.map { $0 as! CTFont })) // swiftlint:disable:this force_cast
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

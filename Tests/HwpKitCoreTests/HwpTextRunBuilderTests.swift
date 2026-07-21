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

        func testBuildCapsOutputToMaxCharacters() throws {
            let paragraph = paragraph(text: String(repeating: "가", count: 5000), runs: [(0, 0)])
            let textBuilder = builder(shapes: [0: try charShape()])

            let full = textBuilder.build(paragraph: paragraph)
            let capped = textBuilder.build(paragraph: paragraph, maxCharacters: 100)

            expect(full.string.count) == 5000
            expect(capped.string.count) == 100
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

        /// ZWJ·결합 마크는 직전 스크립트를 상속해 폰트 run이 갈리지 않는다 —
        /// run 경계가 생기면 CoreText가 결합 글리프(이모지 ZWJ 시퀀스)를 못 만든다.
        func testJoinerAndCombiningMarkInheritSurroundingScript() throws {
            let joined = paragraph(text: "👨\u{200D}👩", runs: [(0, 0)])
            let symbolScaled = try charShape(faceScaleX: [100, 100, 100, 100, 100, 110, 100])
            let joinedResult = builder(shapes: [0: symbolScaled]).build(paragraph: joined)
            let joinedRangeCount = fontRanges(in: joinedResult).count
            expect(joinedRangeCount) == 1

            let marked = paragraph(text: "가\u{302E}", runs: [(0, 0)])
            let englishScaled = try charShape(faceScaleX: [100, 110, 100, 100, 100, 100, 100])
            let markedResult = builder(shapes: [0: englishScaled]).build(paragraph: marked)
            let markedRangeCount = fontRanges(in: markedResult).count
            expect(markedRangeCount) == 1
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
            // CT 밑줄 대신 렌더러 전용 키 (헤어라인 직접 드로잉)
            let value = result.attribute(
                HwpAttributedStringKey.underlineStyle, at: 0, effectiveRange: nil
            ) as? NSNumber

            expect(value?.intValue) == 1
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

        func testHyperlinkSpansNestedFieldWithoutEarlyClosing() throws {
            // 하이퍼링크(코드 3 시작 ~ 코드 4 끝) 안에 다른 필드가 중첩되면,
            // 중첩 필드의 끝 마커(inline 4)가 바깥 링크를 조기 종료하면 안 된다 (#1).
            // a〈hlk 3〉b〈필드 3〉c〈끝 4〉d〈hlk 끝 4〉e — 링크는 b..d 전체.
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            var link = CoreHwp.HwpHyperlink()
            link.url = "http://example.com/outer"
            paraText.charArray =
                "a".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                    + [CoreHwp.HwpChar(type: .extended, value: 3)]
                    + "b".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                    + [CoreHwp.HwpChar(type: .extended, value: 3)]
                    + "c".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                    + [CoreHwp.HwpChar(type: .inline, value: 4)]
                    + "d".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                    + [CoreHwp.HwpChar(type: .inline, value: 4)]
                    + "e".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [
                .hyperLink(link),
                .section(CoreHwp.HwpSectionDef()),
            ]
            var paraCharShape = CoreHwp.HwpParaCharShape()
            paraCharShape.startingIndex = [0]
            paraCharShape.shapeId = [0]
            paragraph.paraCharShape = paraCharShape

            let result = builder(shapes: [0: try charShape()]).build(paragraph: paragraph)
            let string = result.string as NSString
            func hyperlink(at substring: String) -> String? {
                result.attribute(
                    HwpAttributedStringKey.hyperlink,
                    at: string.range(of: substring).location, effectiveRange: nil
                ) as? String
            }

            // "d"는 중첩 필드 끝 뒤 — 조기 종료됐다면 링크가 없다 (회귀 지점).
            expect(hyperlink(at: "d")) == "http://example.com/outer"
            expect(hyperlink(at: "b")) == "http://example.com/outer"
            expect(hyperlink(at: "a")).to(beNil())
            expect(hyperlink(at: "e")).to(beNil())
        }

        func testMemoAnchorRangeSpansNestedField() {
            // memo(코드 3) 안에 하이퍼링크 필드가 중첩: 중첩 종결자(inline 4)가
            // 바깥 memo 앵커를 닫으면 안 된다 (#2). 컨트롤은 스트림에서 8 WCHAR —
            // memo 시작 후 위치 8, 최종 종결자 위치 27이 앵커 범위다.
            var link = CoreHwp.HwpHyperlink()
            link.url = "http://example.com"
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray =
                [CoreHwp.HwpChar(type: .extended, value: 3)]
                    + "a".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                    + [CoreHwp.HwpChar(type: .extended, value: 3)]
                    + "b".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                    + [CoreHwp.HwpChar(type: .inline, value: 4)]
                    + "c".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                    + [CoreHwp.HwpChar(type: .inline, value: 4)]
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [
                .memo(CoreHwp.HwpFieldControl(ctrlId: .memo)),
                .hyperLink(link),
            ]

            let ranges = HwpTextRunBuilder.memoAnchorRanges(in: paragraph)

            expect(ranges) == [UInt32(8) ..< UInt32(27)]
        }

        func testBuildClampsNegativeMaxCharactersToEmpty() throws {
            // 음수 상한은 prefix가 트랩하므로 0으로 클램프해 빈 결과를 낸다 (R45 #3).
            let paragraph = paragraph(text: "hello", runs: [(0, 0)])
            let result = builder(shapes: [0: try charShape()]).build(
                paragraph: paragraph, maxCharacters: -5
            )
            expect(result.length) == 0
        }

        func testBuildDoesNotSplitSurrogatePairAtMaxCharacters() throws {
            // "ab😀"의 😀는 UTF-16 2유닛(high+low). 상한이 그 사이(3)를 자르면 lead
            // 서로게이트만 남아 예전엔 U+FFFD로 손상됐다 — 이제 온전한 "ab"만 남긴다.
            // 상한이 이모지를 넘으면(4) 온전히 유지한다 (R46 #1).
            let paragraph = paragraph(text: "ab😀", runs: [(0, 0)])
            let runBuilder = builder(shapes: [0: try charShape()])

            let split = runBuilder.build(paragraph: paragraph, maxCharacters: 3)
            expect(split.string) == "ab"
            expect(split.string.unicodeScalars.contains("\u{FFFD}")) == false

            let whole = runBuilder.build(paragraph: paragraph, maxCharacters: 4)
            expect(whole.string) == "ab😀"
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

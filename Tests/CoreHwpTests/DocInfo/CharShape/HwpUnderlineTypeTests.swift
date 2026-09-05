@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 밑줄 종류(표 33, bit 2~3)의 raw 값 배치 — 한글.app이 '글자 위'를 스펙 그대로
/// **3**으로 저장하는데 종전 enum은 `above = 2`라 그런 문서가 통째로 거부됐다
/// (#149). 2비트 네 값이 전부 케이스를 갖는지, 실측 문서 쌍(HWP·HWPX)이
/// 같은 케이스로 모이는지, 뷰어 옵션에서도 열리는지를 고정한다.
final class HwpUnderlineTypeTests: XCTestCase {
    /// 2비트 필드의 네 값 전부가 throw 없이 케이스를 갖는다 — 하나라도 빠지면
    /// `HwpCharShapeProperty.load`가 `invalidRawValueForEnum`을 던져 DocInfo
    /// 전체, 곧 문서 전체가 거부된다.
    func testEveryTwoBitRawValueHasACase() throws {
        let expected: [(raw: UInt32, type: HwpUnderlineType)] = [
            (0, .none), (1, .under), (2, .undefined2), (3, .above),
        ]
        for (raw, type) in expected {
            let property = try HwpCharShapeProperty.load(raw << 2)
            expect(property.underlineType).to(equal(type), description: "raw \(raw)")
            expect(property.rawValue) == raw << 2
        }
        expect(HwpUnderlineType.above.rawValue) == 3
        expect(HwpUnderlineType(rawValue: 4)).to(beNil())
    }

    /// typed 필드 → bit field 재합성이 스펙 값(글자 위 = 3)을 그대로 적는다 —
    /// HWPX 매퍼가 이 경로로 `rawValue`를 만든다.
    func testSynthesizedRawValueRoundTripsEveryUnderlineType() throws {
        for type in [HwpUnderlineType.none, .under, .undefined2, .above] {
            var property = HwpCharShapeProperty()
            property.underlineType = type
            let raw = property.synthesizedRawValue
            expect((raw >> 2) & 0b11) == UInt32(type.rawValue)
            expect(try HwpCharShapeProperty.load(raw).underlineType) == type
        }
    }

    /// 한글.app 12.30이 밑줄 위치 '위쪽'으로 저장한 실측 문서 — charShape[7]의
    /// 속성이 `0x0000000c`(밑줄 종류 3, 밑줄 모양 0)다.
    func testUnderlineAboveFixtureParsesSpecValueThree() throws {
        let hwp = try openHwp(#file, "underline-above")
        let shapes = hwp.docInfo.idMappings.charShapeArray

        expect(shapes.count) == 8
        expect(shapes[7].property.rawValue) == 0x0000_000C
        expect(shapes[7].property.underlineType) == .above
        expect(shapes[7].property.underlineShape) == 0
        expect(shapes[0 ..< 7].map(\.property.underlineType)).to(
            allPass { $0 == HwpUnderlineType.none }
        )
        // 본문 문단이 그 글자 모양을 쓴다 — 밑줄이 실제 텍스트에 걸려 있다.
        let paragraph = try XCTUnwrap(hwp.sectionArray.first?.paragraph.first)
        expect(paragraph.paraCharShape.shapeId).to(contain(7))
    }

    /// 종전에는 `HwpLoadOptions.viewer`(부분 복구)로도 살아나지 않았다 — DocInfo는
    /// 복구 대상이 아니라서다. 두 옵션 모두 같은 결과로 열려야 한다.
    func testUnderlineAboveFixtureOpensWithDefaultAndViewerOptions() throws {
        let path = FixtureLoader.root
            .appendingPathComponent("underline-above")
            .appendingPathComponent("document.hwp")
            .path

        for options in [HwpLoadOptions.default, .viewer] {
            let hwp = try HwpFile(fromPath: path, options: options)
            expect(hwp.docInfo.idMappings.charShapeArray[7].property.underlineType) == .above
            expect(hwp.parseDiagnostics()).to(beEmpty())
        }
    }

    /// 같은 문서를 한글.app이 HWPX로 저장하면 `<hh:underline type="TOP"/>`이다 —
    /// 매퍼가 같은 `.above`로 모으고, 합성 `rawValue`의 bit 2~3도 스펙 값 3이다.
    func testUnderlineAboveHwpxPairMapsTopToAbove() throws {
        let hwpx = try openHwpx(#file, "underline-above")
        let shapes = hwpx.docInfo.idMappings.charShapeArray

        expect(shapes.count) == 8
        expect(shapes[7].property.underlineType) == .above
        expect((shapes[7].property.rawValue >> 2) & 0b11) == 3
        expect(shapes[7].underlineColor) == HwpColor(0, 0, 0)
    }

    /// 합성 header.xml에서도 `TOP`이 `.above`(3)로, `BOTTOM`이 `.under`(1)로 간다.
    func testHeaderMapperMapsUnderlineTopToAbove() throws {
        let xml = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:underline type=\"BOTTOM\"",
            with: "<hh:underline type=\"TOP\""
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(xml)
        let property = docInfo.idMappings.charShapeArray[0].property

        expect(property.underlineType) == .above
        expect((property.rawValue >> 2) & 0b11) == 3
        expect(try HwpCharShapeProperty.load(property.rawValue).underlineType) == .above
    }

    /// 취소선 견본의 밑줄 종류 raw 2는 글자 위가 아니다 — 두 픽스처 모두 같은
    /// 값(`0x40008` = 밑줄 종류 2 + 취소선 1)이고 한글.app의 HWPX 재저장본은
    /// 밑줄 없음(`NONE`) + `strikeout`이다. 케이스는 값을 보존만 한다.
    func testStrikethroughSamplesKeepUndefinedRawTwo() throws {
        for id in ["CharShape", "CharShapeProperty"] {
            let hwp = try openHwp(#file, id)
            let property = hwp.docInfo.idMappings.charShapeArray[18].property
            expect(property.rawValue).to(equal(0x0004_0008), description: id)
            expect(property.underlineType).to(equal(.undefined2), description: id)
            expect(property.strikethrough).to(equal(1), description: id)

            let hwpx = try openHwpx(#file, id)
            let paired = hwpx.docInfo.idMappings.charShapeArray[18].property
            expect(paired.underlineType).to(equal(HwpUnderlineType.none), description: id)
            expect(paired.strikethrough).to(equal(1), description: id)
        }
    }
}

import CoreHwp
import Nimble
import XCTest

final class ParaShapePropertyInfoTests: XCTestCase {
    func testParaShapeProperty1InfoDecodesParagraphBorderBits() throws {
        let property = try HwpParaShapeProperty1.load(0x3000_0000)

        expect(property.rawValue) == 0x3000_0000
        expect(property.borderConnect) == true
        expect(property.borderIgnoreMargin) == true

        let defaultProperty = HwpParaShapeProperty1(rawValue: 0)
        expect(defaultProperty.borderConnect) == false
        expect(defaultProperty.borderIgnoreMargin) == false
    }

    func testParaShapeProperty1DefaultInitializerUsesEmptyBitField() {
        let property = HwpParaShapeProperty1()

        expect(property.rawValue) == 0
        expect(property.borderConnect) == false
        expect(property.borderIgnoreMargin) == false
    }

    /// 문단 수준 (표 44 bit 25-27)은 **0-기반 저장값**이다 — 사람이 읽는 수준은 +1.
    func testParaShapeProperty1DecodesZeroBasedHeadingLevel() throws {
        // 머리 모양 종류 1(개요) + 수준 비트 0..7
        for level in UInt32(0) ... 7 {
            let raw = (1 << 23) | (level << 25)
            let property = try HwpParaShapeProperty1.load(raw)
            expect(property.headingTypeRawValue) == 1
            expect(property.headingLevelRawValue) == level
        }
        // 3비트라 담기는 범위는 0...7 = 1수준~8수준. 그 위 비트는 침범하지 않는다.
        expect(HwpParaShapeProperty1(rawValue: 0xFFFF_FFFF).headingLevelRawValue) == 7
        expect(HwpParaShapeProperty1(rawValue: 0).headingLevelRawValue) == 0
        // 이웃 비트 (머리 모양 종류 23-24, 문단 테두리 연결 28)와 겹치지 않는다.
        expect(HwpParaShapeProperty1(rawValue: 0x0180_0000).headingLevelRawValue) == 0
        expect(HwpParaShapeProperty1(rawValue: 1 << 28).headingLevelRawValue) == 0
    }

    /// 저장 기점은 실측이 확정한다 (#77) — 헌법주석의 `개요 N` 스타일이 가리키는
    /// paraShape의 수준 비트가 정확히 `N - 1`이다. 스펙의 "1수준~7수준"은 의미
    /// 범위 표기일 뿐 저장 기점이 아니다.
    func testOutlineStyleNamesMapToZeroBasedLevelBits() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let idMappings = hwp.docInfo.idMappings

        var seen: [String: UInt32] = [:]
        for style in idMappings.styleArray where style.styleLocalName.hasPrefix("개요 ") {
            let paraShape = idMappings.paraShapeArray[Int(style.paraShapeId)]
            guard paraShape.property1Info.headingTypeRawValue == 1 else { continue }
            seen[style.styleLocalName] = paraShape.property1Info.headingLevelRawValue
        }

        expect(seen) == [
            "개요 1": 0, "개요 2": 1, "개요 3": 2, "개요 4": 3,
            "개요 5": 4, "개요 6": 5, "개요 7": 6,
        ]
        // `개요 8`·`개요 9`는 문단 머리 모양이 개요로 설정돼 있지 않아 (raw 0x180)
        // 비트 경로로는 원리적으로 잡히지 않는다 — 스타일 이름 폴백이 상시 병행
        // 경로여야 하는 이유다 (HwpKitCore의 `HwpOutlineCollector`).
        let outlineEight = try XCTUnwrap(
            idMappings.styleArray.first { $0.styleLocalName == "개요 8" }
        )
        let eightShape = idMappings.paraShapeArray[Int(outlineEight.paraShapeId)]
        expect(eightShape.property1) == 0x180
        expect(eightShape.property1Info.headingTypeRawValue) == 0
    }

    /// 문단 수준 비트 분포와 스타일 이름 분포가 **개수까지 일치**한다 (#77 실측).
    func testHeadingLevelDistributionMatchesStyleNameDistribution() throws {
        let hwp = try openHwp(#file, "legacy-common-control-property")
        let idMappings = hwp.docInfo.idMappings

        var levelCounts: [UInt32: Int] = [:]
        var styleCounts: [String: Int] = [:]
        for section in hwp.displaySectionArray {
            for paragraph in section.paragraph {
                let paraShape = idMappings.paraShapeArray[Int(paragraph.paraHeader.paraShapeId)]
                guard paraShape.property1Info.headingTypeRawValue == 1 else { continue }
                levelCounts[paraShape.property1Info.headingLevelRawValue, default: 0] += 1
                let style = idMappings.styleArray[Int(paragraph.paraHeader.paraStyleId)]
                styleCounts[style.styleLocalName, default: 0] += 1
            }
        }

        expect(levelCounts.values.reduce(0, +)) == 1944
        expect(levelCounts) == [0: 280, 1: 512, 2: 486, 3: 301, 4: 244, 5: 100, 6: 21]
        expect(styleCounts) == [
            "개요 1": 280, "개요 2": 512, "개요 3": 486, "개요 4": 301,
            "개요 5": 244, "개요 6": 100, "개요 7": 21,
        ]
    }

    func testParaShapeProperty1InfoIsWiredFromRealFixture() throws {
        let hwp = try openHwp(#file, "noori")
        let paraShapes = hwp.docInfo.idMappings.paraShapeArray

        expect(paraShapes).toNot(beEmpty())
        expect(paraShapes[0].property1) == 128
        expect(paraShapes[0].property1Info.rawValue) == paraShapes[0].property1
        expect(paraShapes[0].property1Info.borderConnect) == false
        expect(paraShapes[0].property1Info.borderIgnoreMargin) == false
        expect(paraShapes.contains { $0.property1Info.borderConnect }) == false
        expect(paraShapes.contains { $0.property1Info.borderIgnoreMargin }) == false
    }
}

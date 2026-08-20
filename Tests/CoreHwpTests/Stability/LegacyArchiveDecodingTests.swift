@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// main이 인코딩한 아카이브(신규 키 부재)는 브랜치 디코더가 기본값으로
/// 폴백해 keyNotFound 없이 열려야 한다 (R61 #1).
final class LegacyArchiveDecodingTests: XCTestCase {
    private func legacyJSON(
        of value: some Encodable, removingKey key: String
    ) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testHwpFileDecodesLegacyArchiveWithoutViewSectionArray() throws {
        let legacy = try legacyJSON(of: HwpFile(), removingKey: "viewSectionArray")

        let decoded = try JSONDecoder().decode(HwpFile.self, from: legacy)

        expect(decoded.viewSectionArray).to(beEmpty())
        expect(decoded.sectionArray.count) == 1
        expect(decoded.displaySectionArray.count) == 1
    }

    func testHwpParagraphDecodesLegacyArchiveWithoutParseFailure() throws {
        let legacy = try legacyJSON(of: HwpParagraph(), removingKey: "parseFailure")

        let decoded = try JSONDecoder().decode(HwpParagraph.self, from: legacy)

        expect(decoded.parseFailure).to(beNil())
        expect(decoded) == HwpParagraph()
    }

    func testHwpSectionDecodesLegacyArchiveWithoutParseFailure() throws {
        let legacy = try legacyJSON(of: HwpSection(), removingKey: "parseFailure")

        let decoded = try JSONDecoder().decode(HwpSection.self, from: legacy)

        expect(decoded.parseFailure).to(beNil())
        expect(decoded.paragraph.count) == 1
    }

    func testParseFailurePlaceholderRoundTripsThroughCodable() throws {
        let placeholder = HwpParagraph.parseFailurePlaceholder(
            record: HwpRecord(tagId: 66, level: 0, payload: Data([0xAA])),
            error: .invalidRecordTree(reason: "spec")
        )

        let decoded = try JSONDecoder().decode(
            HwpParagraph.self,
            from: JSONEncoder().encode(placeholder)
        )

        expect(decoded.parseFailure) == placeholder.parseFailure
        expect(decoded.paraText).to(beNil())
        expect(decoded) == placeholder
    }

    func testHwpReadLimitsDecodeLegacyArchiveWithoutAggregateKey() throws {
        let legacy = try legacyJSON(
            of: HwpReadLimits.default, removingKey: "maxAggregateStreamBytes"
        )

        let decoded = try JSONDecoder().decode(HwpReadLimits.self, from: legacy)

        expect(decoded.maxAggregateStreamBytes) == 1024 * 1024 * 1024
        expect(decoded.maxCompressedStreamBytes) == HwpReadLimits.default.maxCompressedStreamBytes
    }

    func testHwpReadLimitsDecodeLegacyArchiveWithoutNestingDepthKey() throws {
        let legacy = try legacyJSON(
            of: HwpReadLimits.default, removingKey: "maxNestingDepth"
        )

        let decoded = try JSONDecoder().decode(HwpReadLimits.self, from: legacy)

        expect(decoded.maxNestingDepth) == 64
        expect(decoded.maxAggregateStreamBytes) == HwpReadLimits.default.maxAggregateStreamBytes
    }

    func testCommonCtrlPropertyInfoDecodesLegacyArchiveWithoutAnchorEnums() throws {
        let original = try HwpCommonCtrlPropertyInfo.load(0)
        let encoded = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        for key in [
            "verticalRelativeTo", "verticalAlignment",
            "horizontalRelativeTo", "horizontalAlignment",
        ] {
            json.removeValue(forKey: key)
        }
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(HwpCommonCtrlPropertyInfo.self, from: legacyData)

        expect(decoded.verticalRelativeTo).toNot(beNil())
        expect(decoded) == original
    }

    func testTableCellHeaderDecodesLegacyArchiveWithoutCellProperty() throws {
        let trailing = Data(count: 26)
        let original = HwpTableCellHeader(
            paragraphCount: 1,
            property: 0,
            propertyInfo: try HwpListHeaderProperty.load(0),
            listHeaderWidthRef: 0,
            cellPropertyInfo: HwpTableCellHeaderProperty(rawValue: 0),
            isHeader: false,
            cellProperty: HwpTableCellProperty.decode(from: trailing),
            rawTrailing: trailing,
            rawPayload: Data(),
            unknownChildren: []
        )
        expect(original.cellProperty).toNot(beNil())
        let legacy = try legacyJSON(of: original, removingKey: "cellProperty")

        let decoded = try JSONDecoder().decode(HwpTableCellHeader.self, from: legacy)

        expect(decoded.cellProperty) == original.cellProperty
    }

    func testOtherControlDecodesLegacyArchiveWithoutTypedNumberPayloads() throws {
        let trailing = Data([1, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0])
        let original = HwpOtherControl(
            ctrlId: .newNumber,
            rawTrailing: trailing,
            rawPayload: Data(),
            ctrlDataRecords: [],
            unknownChildren: []
        )
        let encoded = try JSONEncoder().encode(original)

        let decoded = try JSONDecoder().decode(HwpOtherControl.self, from: encoded)

        expect(decoded.newNumberInfo?.number) == 7
        expect(decoded.numberingInfo?.number) == 7
    }

    /// 글상자 리스트의 textBoxInfo는 부모(HwpShapeComponent) 디코더가 재수화한다
    /// — 파스가 표 90을 무조건 파생하므로 legacy 키 부재와 멱등 (R62 #4, R64 #3).
    func testShapeComponentRehydratesTextBoxInfoFromLegacyArchive() throws {
        var headerData = Data([1, 0, 0, 0, 0, 0, 0, 0])
        headerData += Data([1, 0, 2, 0, 3, 0, 4, 0, 100, 0, 0, 0])
        let header = try HwpListHeader.load(headerData)
        let component = HwpShapeComponent(
            rawCtrlId: nil,
            ctrlId: nil,
            rawPayload: Data(),
            rawTrailing: nil,
            pictureArray: [],
            oleArray: [],
            oleRecords: [],
            ctrlDataRecords: [],
            textBoxListArray: [HwpListControlList(
                header: header,
                headerRawPayload: headerData,
                headerUnknownChildren: [],
                paragraphArray: [],
                textBoxInfo: nil
            )],
            unknownChildren: []
        )

        let decoded = try JSONDecoder().decode(
            HwpShapeComponent.self, from: JSONEncoder().encode(component)
        )

        expect(decoded.textBoxListArray.first?.textBoxInfo) == HwpTextBoxListInfo(
            leftMargin: 1, rightMargin: 2, topMargin: 3, bottomMargin: 4, maxTextWidth: 100
        )
    }

    /// 글상자 아닌 리스트(HwpListControl 소속 머리말/꼬리말)는 단독 디코딩에서
    /// 재수화하지 않는다 — "글상자가 아니면 nil" 계약 (R64 #3).
    func testListControlListKeepsNilTextBoxInfoWithoutShapeComponentContext() throws {
        var headerData = Data([1, 0, 0, 0, 0, 0, 0, 0])
        headerData += Data(repeating: 0x11, count: 26)
        let header = try HwpListHeader.load(headerData)
        let original = HwpListControlList(
            header: header,
            headerRawPayload: headerData,
            headerUnknownChildren: [],
            paragraphArray: [],
            textBoxInfo: nil
        )

        let decoded = try JSONDecoder().decode(
            HwpListControlList.self, from: JSONEncoder().encode(original)
        )

        expect(decoded.textBoxInfo).to(beNil())
        expect(decoded) == original
    }

    /// main 파서는 표 40의 글자 모양 ID를 읽지 않아 그 뒤 필드가 전부 4바이트씩
    /// 밀려 저장됐다 — headCharShapeId만 −1로 채우면 char 등이 쓰레기로 남으므로
    /// rawPayload에서 전량 재파스해야 한다 (R66 #2, R72 #2).
    func testHwpBulletReparsesShiftedLegacyFieldsFromRawPayload() throws {
        var payload = Data([1, 2, 3, 4, 5, 6, 7, 8]) // info
        payload += Data([7, 0, 0, 0]) // headCharShapeId = 7
        payload += Data([0x00, 0xAC]) // char = "가"
        payload += Data([0, 0, 0, 0]) // imageId
        payload += Data([0, 0, 0, 0]) // imageProperty
        payload += Data([0x13, 0x27]) // checkChar = "✓"
        let bullet = try HwpBullet.load(payload)
        expect(bullet.headCharShapeId) == 7
        expect(bullet.char) == "가"

        // main 아카이브 모사: 키를 지우고 char를 4바이트 밀려 읽힌 값으로 오염
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(bullet)) as? [String: Any]
        )
        json.removeValue(forKey: "headCharShapeId")
        json["char"] = "\u{0007}"
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(HwpBullet.self, from: legacy)

        expect(decoded.headCharShapeId) == 7
        expect(decoded.char) == "가"
        expect(decoded.checkChar) == "✓"
    }

    func testHwpBulletDecodesLegacyArchiveWithoutHeadCharShapeId() throws {
        let bullet = HwpBullet(
            rawPayload: Data([1]),
            info: [0, 0, 0, 0, 0, 0, 0, 0],
            headCharShapeId: 7,
            char: "-",
            charRawPayload: Data([2]),
            imageId: 0,
            imageProperty: [0, 0, 0, 0],
            checkChar: "*",
            checkCharRawPayload: Data([3]),
            undocumentedTrailing: []
        )
        let legacy = try legacyJSON(of: bullet, removingKey: "headCharShapeId")

        let decoded = try JSONDecoder().decode(HwpBullet.self, from: legacy)

        expect(decoded.headCharShapeId) == -1
        expect(decoded.char) == "-"
        expect(decoded.checkChar) == "*"
        expect(decoded.info) == [0, 0, 0, 0, 0, 0, 0, 0]
    }
}

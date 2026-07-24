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

    func testHwpReadLimitsDecodeLegacyArchiveWithoutAggregateKey() throws {
        let legacy = try legacyJSON(
            of: HwpReadLimits.default, removingKey: "maxAggregateStreamBytes"
        )

        let decoded = try JSONDecoder().decode(HwpReadLimits.self, from: legacy)

        expect(decoded.maxAggregateStreamBytes) == 1024 * 1024 * 1024
        expect(decoded.maxCompressedStreamBytes) == HwpReadLimits.default.maxCompressedStreamBytes
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

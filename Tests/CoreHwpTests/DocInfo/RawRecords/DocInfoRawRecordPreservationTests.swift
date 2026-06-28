@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DocInfoRawRecordPreservationTests: XCTestCase {
    func testDistributeDocDataPreservesUnknownRecordTreeThroughCodable() throws {
        let payload = Data([0xD1, 0x57, 0x00, 0x01])
        let childPayload = Data([0xC1, 0xC2])
        let grandchildPayload = Data([0xC3])

        let child = HwpRecord(tagId: 0x315, level: 1, payload: childPayload)
        child.children = [
            HwpRecord(tagId: 0x316, level: 2, payload: grandchildPayload),
        ]

        let distributeDocData = try HwpDistributeDocData.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.distributeDocData.rawValue,
            payload: payload,
            children: [child]
        ))
        let decoded = try JSONDecoder().decode(
            HwpDistributeDocData.self,
            from: JSONEncoder().encode(distributeDocData)
        )

        assertUnknownRecordTree(
            distributeDocData.unknownChildren,
            childTagId: 0x315,
            childPayload: childPayload,
            grandchildTagId: 0x316,
            grandchildPayload: grandchildPayload
        )
        expect(distributeDocData.rawPayload) == payload
        expect(distributeDocData.distributeDocDataInfo?.values) == [0x0100_57D1]
        expect(distributeDocData.distributeDocDataInfo?.valuesRawPayload) == payload
        expect(distributeDocData.distributeDocDataInfo?.rawTrailing).to(beEmpty())
        assertUnknownRecordTree(
            decoded.unknownChildren,
            childTagId: 0x315,
            childPayload: childPayload,
            grandchildTagId: 0x316,
            grandchildPayload: grandchildPayload
        )
        expect(decoded.rawPayload) == payload
        expect(decoded.distributeDocDataInfo?.values) == [0x0100_57D1]
        expect(decoded.distributeDocDataInfo?.valuesRawPayload) == payload
        expect(decoded.distributeDocDataInfo?.rawTrailing).to(beEmpty())
    }

    func testMalformedDistributeDocDataPayloadIsPreservedWithoutParsedInfo() throws {
        let payload = Data([0xD1, 0x57, 0x00])
        let distributeDocData = try HwpDistributeDocData.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.distributeDocData.rawValue,
            payload: payload,
            children: []
        ))

        expect(distributeDocData.distributeDocDataInfo).to(beNil())
        expect(distributeDocData.rawPayload) == payload
    }

    func testDocDataPreservesForbiddenCharChildrenAndUnknownChildren() throws {
        let payload = Data([0xAA, 0xBB])
        let forbiddenPayload = Data([0x01, 0x02])
        let forbiddenGrandchildPayload = Data([0x03])
        let unknownPayload = Data([0x04, 0x05])
        let unknownGrandchildPayload = Data([0x06])

        let forbiddenChild = HwpRecord(
            tagId: HwpDocInfoTag.forbiddenChar.rawValue,
            level: 1,
            payload: forbiddenPayload
        )
        forbiddenChild.children = [
            HwpRecord(tagId: 0x302, level: 2, payload: forbiddenGrandchildPayload),
        ]

        let unknownChild = HwpRecord(tagId: 0x303, level: 1, payload: unknownPayload)
        unknownChild.children = [
            HwpRecord(tagId: 0x304, level: 2, payload: unknownGrandchildPayload),
        ]

        let docData = try HwpDocData.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.docData.rawValue,
            payload: payload,
            children: [forbiddenChild, unknownChild]
        ))
        let decoded = try JSONDecoder().decode(
            HwpDocData.self,
            from: JSONEncoder().encode(docData)
        )
        let expectedForbiddenUnknownChildren = expectedForbiddenCharUnknownChildren(
            forbiddenGrandchildPayload
        )
        let expectedUnknownChildren = expectedDocDataUnknownChildren(
            payload: unknownPayload,
            grandchildPayload: unknownGrandchildPayload
        )

        expect(docData.rawPayload) == payload
        expect(docData.forbiddenCharArray.map(\.rawPayload)) == [forbiddenPayload]
        expect(docData.forbiddenCharArray.map(\.data)) == [forbiddenPayload]
        expect(docData.forbiddenCharArray.first?.unknownChildren ?? []) ==
            expectedForbiddenUnknownChildren
        expect(docData.unknownChildren) == expectedUnknownChildren
        expect(decoded.rawPayload) == payload
        expect(decoded.forbiddenCharArray.map(\.rawPayload)) == [forbiddenPayload]
        expect(decoded.forbiddenCharArray.first?.unknownChildren ?? []) ==
            expectedForbiddenUnknownChildren
        expect(decoded.unknownChildren) == expectedUnknownChildren
    }

    func testMemoShapePreservesUnknownRecordTreeThroughCodable() throws {
        let payload = Data([0xAA, 0xBB])
        let childPayload = Data([0xB1, 0xB2])
        let grandchildPayload = Data([0xB3])

        let child = HwpRecord(tagId: 0x318, level: 1, payload: childPayload)
        child.children = [
            HwpRecord(tagId: 0x319, level: 2, payload: grandchildPayload),
        ]

        let memoShape = try HwpMemoShape.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.memoShape.rawValue,
            payload: payload,
            children: [child]
        ))
        let decoded = try JSONDecoder().decode(
            HwpMemoShape.self,
            from: JSONEncoder().encode(memoShape)
        )

        expect(memoShape.rawPayload) == payload
        expect(memoShape.shapeInfo).to(beNil())
        assertUnknownRecordTree(
            memoShape.unknownChildren,
            childTagId: 0x318,
            childPayload: childPayload,
            grandchildTagId: 0x319,
            grandchildPayload: grandchildPayload
        )
        expect(decoded.rawPayload) == payload
        expect(decoded.shapeInfo).to(beNil())
        assertUnknownRecordTree(
            decoded.unknownChildren,
            childTagId: 0x318,
            childPayload: childPayload,
            grandchildTagId: 0x319,
            grandchildPayload: grandchildPayload
        )
    }

    func testTrackChangePreservesUnknownRecordTreeThroughCodable() throws {
        let payload = Data([0x71, 0x72, 0x73])
        let childPayload = Data([0x7A, 0x7B])
        let grandchildPayload = Data([0x7C])

        let child = HwpRecord(tagId: 0x316, level: 1, payload: childPayload)
        child.children = [
            HwpRecord(tagId: 0x317, level: 2, payload: grandchildPayload),
        ]

        let trackChange = try HwpTrackChange.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.trackChange.rawValue,
            payload: payload,
            children: [child]
        ))
        let decoded = try JSONDecoder().decode(
            HwpTrackChange.self,
            from: JSONEncoder().encode(trackChange)
        )

        assertUnknownRecordTree(
            trackChange.unknownChildren,
            childTagId: 0x316,
            childPayload: childPayload,
            grandchildTagId: 0x317,
            grandchildPayload: grandchildPayload
        )
        expect(trackChange.rawPayload) == payload
        assertUnknownRecordTree(
            decoded.unknownChildren,
            childTagId: 0x316,
            childPayload: childPayload,
            grandchildTagId: 0x317,
            grandchildPayload: grandchildPayload
        )
        expect(decoded.rawPayload) == payload
    }

    func testTrackChangeContentPreservesUnknownRecordTreeThroughCodable() throws {
        let payload = Data([0x11, 0x22])
        let childPayload = Data([0xC0, 0xC1])
        let grandchildPayload = Data([0xC2])

        let child = HwpRecord(tagId: 0x301, level: 1, payload: childPayload)
        child.children = [
            HwpRecord(tagId: 0x302, level: 2, payload: grandchildPayload),
        ]

        let content = try HwpTrackChangeContent.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.trackChangeContent.rawValue,
            payload: payload,
            children: [child]
        ))
        let decoded = try JSONDecoder().decode(
            HwpTrackChangeContent.self,
            from: JSONEncoder().encode(content)
        )

        expect(content.rawPayload) == payload
        expect(content.contentInfo).to(beNil())
        assertUnknownRecordTree(
            content.unknownChildren,
            childTagId: 0x301,
            childPayload: childPayload,
            grandchildTagId: 0x302,
            grandchildPayload: grandchildPayload
        )
        expect(decoded.rawPayload) == payload
        expect(decoded.contentInfo).to(beNil())
        assertUnknownRecordTree(
            decoded.unknownChildren,
            childTagId: 0x301,
            childPayload: childPayload,
            grandchildTagId: 0x302,
            grandchildPayload: grandchildPayload
        )
    }

    func testTrackChangeAuthorPreservesUnknownRecordTreeThroughCodable() throws {
        let payload = Data([0x33, 0x44, 0x55])
        let childPayload = Data([0xA0, 0xA1, 0xA2])
        let grandchildPayload = Data([0xA3])

        let child = HwpRecord(tagId: 0x303, level: 1, payload: childPayload)
        child.children = [
            HwpRecord(tagId: 0x304, level: 2, payload: grandchildPayload),
        ]

        let author = try HwpTrackChangeAuthor.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.trackChangeAuthor.rawValue,
            payload: payload,
            children: [child]
        ))
        let decoded = try JSONDecoder().decode(
            HwpTrackChangeAuthor.self,
            from: JSONEncoder().encode(author)
        )

        expect(author.rawPayload) == payload
        expect(author.authorInfo).to(beNil())
        assertUnknownRecordTree(
            author.unknownChildren,
            childTagId: 0x303,
            childPayload: childPayload,
            grandchildTagId: 0x304,
            grandchildPayload: grandchildPayload
        )
        expect(decoded.rawPayload) == payload
        expect(decoded.authorInfo).to(beNil())
        assertUnknownRecordTree(
            decoded.unknownChildren,
            childTagId: 0x303,
            childPayload: childPayload,
            grandchildTagId: 0x304,
            grandchildPayload: grandchildPayload
        )
    }

    func testForbiddenCharPreservesUnknownRecordTreeThroughCodable() throws {
        let payload = Data([0x45, 0x46, 0x47])
        let childPayload = Data([0x48, 0x49])
        let grandchildPayload = Data([0x4A])

        let child = HwpRecord(tagId: 0x305, level: 1, payload: childPayload)
        child.children = [
            HwpRecord(tagId: 0x306, level: 2, payload: grandchildPayload),
        ]

        let forbiddenChar = try HwpForbiddenChar.load(rawDocInfoRecord(
            tagId: HwpDocInfoTag.forbiddenChar.rawValue,
            payload: payload,
            children: [child]
        ))
        let decoded = try JSONDecoder().decode(
            HwpForbiddenChar.self,
            from: JSONEncoder().encode(forbiddenChar)
        )

        expect(forbiddenChar.rawPayload) == payload
        expect(forbiddenChar.data) == payload
        assertUnknownRecordTree(
            forbiddenChar.unknownChildren,
            childTagId: 0x305,
            childPayload: childPayload,
            grandchildTagId: 0x306,
            grandchildPayload: grandchildPayload
        )
        expect(decoded.rawPayload) == payload
        expect(decoded.data) == payload
        assertUnknownRecordTree(
            decoded.unknownChildren,
            childTagId: 0x305,
            childPayload: childPayload,
            grandchildTagId: 0x306,
            grandchildPayload: grandchildPayload
        )
    }
}

private func rawDocInfoRecord(
    tagId: UInt32,
    payload: Data,
    children: [HwpRecord]
) -> HwpRecord {
    rawRecord(tagId: tagId, level: 0, payload: payload, children: children)
}

private func assertUnknownRecordTree(
    _ records: [HwpUnknownRecord],
    childTagId: UInt32,
    childPayload: Data,
    grandchildTagId: UInt32,
    grandchildPayload: Data
) {
    expect(records) == [
        expectedUnknownRecord(
            tagId: childTagId,
            level: 1,
            payload: childPayload,
            children: [
                rawRecord(tagId: grandchildTagId, level: 2, payload: grandchildPayload),
            ]
        ),
    ]
}

private func expectedForbiddenCharUnknownChildren(_ payload: Data) -> [HwpUnknownRecord] {
    [
        expectedUnknownRecord(tagId: 0x302, level: 2, payload: payload),
    ]
}

private func expectedDocDataUnknownChildren(
    payload: Data,
    grandchildPayload: Data
) -> [HwpUnknownRecord] {
    [
        expectedUnknownRecord(
            tagId: 0x303,
            level: 1,
            payload: payload,
            children: [
                rawRecord(tagId: 0x304, level: 2, payload: grandchildPayload),
            ]
        ),
    ]
}

private func expectedUnknownRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpUnknownRecord {
    HwpUnknownRecord(rawRecord(tagId: tagId, level: level, payload: payload, children: children))
}

private func rawRecord(
    tagId: UInt32,
    level: UInt32,
    payload: Data,
    children: [HwpRecord] = []
) -> HwpRecord {
    let record = HwpRecord(tagId: tagId, level: level, payload: payload)
    record.children = children
    return record
}

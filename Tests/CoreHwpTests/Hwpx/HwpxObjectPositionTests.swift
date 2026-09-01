@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 개체 매핑의 계약 — 위치 오프셋, raw 비트필드, 강등 깊이, 격자 범위.
///
/// `HwpxObjectMapperTests`와 분리한 것은 그 스위트가 SwiftLint
/// `type_body_length` error 상한에 붙어 있어서다.
final class HwpxObjectPositionTests: XCTestCase {
    private func mapTable(vertOffset: String, horzOffset: String) throws -> HwpTable {
        let xml = HwpxObjectFixture.tableXML.replacingOccurrences(
            of: "vertOffset=\"0\" horzOffset=\"0\"",
            with: "vertOffset=\"\(vertOffset)\" horzOffset=\"\(horzOffset)\""
        )
        return try HwpxTableMapper.map(
            HwpxObjectFixture.parse(xml), context: HwpxObjectFixture.makeContext()
        )
    }

    func testUnsignedEncodedNegativeOffsetsArePreserved() throws {
        // 실파일이 쓰는 표현이다 — noori의 표가 -140을 4294967156으로 적는다
        // (부호 리터럴은 픽스처 전수에서 0건). 이 형태를 놓치면 개체가 기준
        // 원점으로 이동한다.
        let table = try mapTable(vertOffset: "4294967156", horzOffset: "4294965648")

        let property = table.commonCtrlProperty
        expect(Int32(bitPattern: property.verticalOffset)) == -140
        expect(Int32(bitPattern: property.horizontalOffset)) == -1648
    }

    func testSignedLiteralOffsetsMapToTheSameBitPattern() throws {
        // 스키마가 허용하는 다른 표현 — 두 형태가 같은 비트열로 접혀야
        // 하류(Int32(bitPattern:))가 같은 좌표를 본다.
        let unsigned = try mapTable(vertOffset: "4294967156", horzOffset: "4294965648")
        let signed = try mapTable(vertOffset: "-140", horzOffset: "-1648")

        expect(signed.commonCtrlProperty.verticalOffset)
            == unsigned.commonCtrlProperty.verticalOffset
        expect(signed.commonCtrlProperty.horizontalOffset)
            == unsigned.commonCtrlProperty.horizontalOffset
    }

    func testObjectPropertyBitfieldIsSynchronizedWithTypedFields() throws {
        // typed 필드만 채우면 raw 두 자리가 0(종이 기준·어울림)으로 남아
        // 같은 모델이 서로 어긋나는 두 값을 동시에 주장한다.
        let property = try mapTable(vertOffset: "0", horzOffset: "0").commonCtrlProperty

        expect(property.property) != 0
        expect(property.propertyInfo.rawValue) == property.property

        let decoded = try HwpCommonCtrlPropertyInfo.load(property.property)
        expect(decoded.treatAsChar) == property.propertyInfo.treatAsChar
        expect(decoded.verticalRelativeTo) == property.propertyInfo.verticalRelativeTo
        expect(decoded.horizontalRelativeTo) == property.propertyInfo.horizontalRelativeTo
        expect(decoded.widthRelativeTo) == property.propertyInfo.widthRelativeTo
        expect(decoded.textWrap) == property.propertyInfo.textWrap
        expect(decoded.numberingCategory) == property.propertyInfo.numberingCategory
    }

    func testSynthesizedLayoutRoundTripsRealBinaryProperties() throws {
        // 합성이 파서의 읽기 순서를 정확히 뒤집는지는 실물 비트열로만
        // 증명된다 — 손으로 쓴 상수와 맞대면 둘이 같이 틀려도 통과한다.
        var raws: [UInt32] = []
        for id in ["noori", "chart", "text-box", "equation"] {
            for section in try openHwp(#file, id).sectionArray {
                for paragraph in section.paragraph {
                    for ctrl in paragraph.ctrlHeaderArray ?? [] {
                        switch ctrl {
                        case let .table(table):
                            raws.append(table.commonCtrlProperty.property)
                        case let .shape(shape):
                            shape.commonCtrlProperty.map { raws.append($0.property) }
                        default:
                            break
                        }
                    }
                }
            }
        }
        // 공허하지 않음 — 실물 값이 여럿이고 서로 다르다.
        expect(raws.count) >= 4
        expect(Set(raws).count) >= 2

        let mask = ~HwpCommonCtrlPropertyInfo.reservedRawValueMask
        for raw in raws {
            expect(try HwpCommonCtrlPropertyInfo.load(raw).synthesizedRawValue) == raw & mask
        }
    }

    func testObjectDemotionDepthHonorsTheCallerLimit() throws {
        // 그림·표 강등도 본문·헤더와 같은 호출자 한도를 따라야 한다. 인자는
        // 이제 컴파일러가 강제하지만 값이 옳은지는 동작으로만 증명된다.
        let capped = HwpLoadOptions(readLimits: HwpReadLimits(maxNestingDepth: 2))
        let picture = HwpxObjectFixture.pictureXML.replacingOccurrences(
            of: "</hp:pic>", with: Self.deepUnknown + "</hp:pic>"
        )
        let table = HwpxObjectFixture.tableXML.replacingOccurrences(
            of: "</hp:tbl>", with: Self.deepUnknown + "</hp:tbl>"
        )

        // 대조군: 기본 한도에서는 네 겹이 그대로 남는다.
        let full = HwpxPictureMapper.map(
            try HwpxObjectFixture.parse(picture),
            context: HwpxObjectFixture.makeContext()
        )
        expect(Self.depth(of: try Self.deepRecord(in: full.unknownChildren))) == 4

        let cappedPicture = HwpxPictureMapper.map(
            try HwpxObjectFixture.parse(picture),
            context: HwpxObjectFixture.makeContext(options: capped)
        )
        expect(Self.depth(of: try Self.deepRecord(in: cappedPicture.unknownChildren))) == 2

        let cappedTable = try HwpxTableMapper.map(
            HwpxObjectFixture.parse(table),
            context: HwpxObjectFixture.makeContext(options: capped)
        )
        expect(Self.depth(of: try Self.deepRecord(in: cappedTable.unknownChildren))) == 2
    }

    private static let deepUnknown = "<ext:deep xmlns:ext=\"urn:x\">"
        + "<ext:a><ext:b><ext:c/></ext:b></ext:a></ext:deep>"

    private static func depth(of record: HwpUnknownRecord) -> Int {
        1 + (record.children.map(depth(of:)).max() ?? 0)
    }

    private static func deepRecord(
        in records: [HwpUnknownRecord]
    ) throws -> HwpUnknownRecord {
        try XCTUnwrap(records.first {
            String(bytes: $0.payload, encoding: .utf8) == "deep"
        })
    }

    func testPositiveObjectOffsetsAreUnchanged() throws {
        // 대조군 — 부호 처리를 넣어도 양수 경로는 종전 값 그대로다.
        let table = try mapTable(vertOffset: "1000", horzOffset: "6411")

        let property = table.commonCtrlProperty
        expect(property.verticalOffset) == 1000
        expect(property.horizontalOffset) == 6411
    }

    func testCellListHeaderBitfieldIsSynchronized() throws {
        // typed 필드만 채우면 raw 두 자리가 0으로 남아 "위 정렬"이라는
        // 어긋난 값이 함께 공개된다 (픽스처 첫 셀은 vertAlign="CENTER").
        let table = try HwpxTableMapper.map(
            HwpxObjectFixture.parse(HwpxObjectFixture.tableXML),
            context: HwpxObjectFixture.makeContext()
        )
        let header = table.cellArray[0].header

        expect(header.propertyInfo.verticalAlignment) == HwpListHeaderVerticalAlignment.center
        expect(header.property) != 0
        expect(header.propertyInfo.rawValue) == header.property
        // 하위 레이아웃(bits 0-6)에 실려야 리더가 폴백으로 되읽는다.
        let decoded = try HwpListHeaderProperty.load(header.property)
        expect(decoded.verticalAlignment) == HwpListHeaderVerticalAlignment.center
    }

    func testTableColumnExtentBeyondTheFieldIsRejected() throws {
        // colAddr·colSpan이 각각 UInt16이라 덮는 폭이 columnCount 필드를 넘을
        // 수 있다 — 클램프하면 조판이 격자 밖 셀을 떨어뜨리거나 옮기는데
        // 문서는 성공한 파스로 보고된다.
        let overflowing = HwpxObjectFixture.tableXML.replacingOccurrences(
            of: "<hp:cellAddr colAddr=\"0\" rowAddr=\"0\"/>",
            with: "<hp:cellAddr colAddr=\"65535\" rowAddr=\"0\"/>"
        )
        expect {
            _ = try HwpxTableMapper.map(
                HwpxObjectFixture.parse(overflowing),
                context: HwpxObjectFixture.makeContext()
            )
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("65,535-column"))
        })

        // 대조군: 원본 픽스처는 그대로 매핑된다.
        let table = try HwpxTableMapper.map(
            HwpxObjectFixture.parse(HwpxObjectFixture.tableXML),
            context: HwpxObjectFixture.makeContext()
        )
        expect(table.tableProperty.columnCount) == 2
    }

    func testObjectInstanceIdPrefersTheDeclaredInstid() throws {
        // instid가 인스턴스 아이디다 — id는 OWPML 요소 식별자라 실물 그림
        // 7개에서 값이 갈린다.
        let withInstid = HwpxObjectFixture.pictureXML.replacingOccurrences(
            of: "id=\"77\" zOrder=\"0\"",
            with: "id=\"77\" instid=\"505652846\" zOrder=\"0\""
        )
        let picture = HwpxPictureMapper.map(
            try HwpxObjectFixture.parse(withInstid),
            context: HwpxObjectFixture.makeContext()
        )
        expect(picture.commonCtrlProperty?.instanceId) == 505_652_846

        // 대조군: 표처럼 instid를 선언하지 않으면 id로 폴백한다 — 없애면
        // 모든 표가 0이 되어 조판의 행 상한 버킷이 뭉개진다.
        let table = try HwpxTableMapper.map(
            HwpxObjectFixture.parse(HwpxObjectFixture.tableXML),
            context: HwpxObjectFixture.makeContext()
        )
        expect(table.commonCtrlProperty.instanceId) == 123
    }
}

@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 개체 공통 속성의 위치 오프셋 계약.
///
/// `HwpxObjectMapperTests`와 분리한 것은 그 스위트가 SwiftLint
/// `type_body_length` error 상한에 붙어 있어서다 — 주제도 배치 좌표 하나로
/// 좁다.
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

    func testPositiveObjectOffsetsAreUnchanged() throws {
        // 대조군 — 부호 처리를 넣어도 양수 경로는 종전 값 그대로다.
        let table = try mapTable(vertOffset: "1000", horzOffset: "6411")

        let property = table.commonCtrlProperty
        expect(property.verticalOffset) == 1000
        expect(property.horizontalOffset) == 6411
    }
}

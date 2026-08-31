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
    func testNegativeObjectOffsetsArePreserved() throws {
        // 오프셋은 음수가 정상값인데 UInt32로 읽으면 파싱 실패로 0이 되어
        // 개체가 기준 원점으로 이동한다 — 하류는 Int32(bitPattern:)로 읽는다.
        let xml = HwpxObjectFixture.tableXML.replacingOccurrences(
            of: "vertOffset=\"0\" horzOffset=\"0\"",
            with: "vertOffset=\"-1000\" horzOffset=\"-2000\""
        )
        let table = try HwpxTableMapper.map(
            HwpxObjectFixture.parse(xml), context: HwpxObjectFixture.makeContext()
        )

        let property = try XCTUnwrap(table.commonCtrlProperty)
        expect(Int32(bitPattern: property.verticalOffset)) == -1000
        expect(Int32(bitPattern: property.horizontalOffset)) == -2000
    }

    func testPositiveObjectOffsetsAreUnchanged() throws {
        // 대조군 — 부호 처리를 넣어도 양수 경로는 종전 값 그대로다.
        let xml = HwpxObjectFixture.tableXML.replacingOccurrences(
            of: "vertOffset=\"0\" horzOffset=\"0\"",
            with: "vertOffset=\"1000\" horzOffset=\"2000\""
        )
        let table = try HwpxTableMapper.map(
            HwpxObjectFixture.parse(xml), context: HwpxObjectFixture.makeContext()
        )

        let property = try XCTUnwrap(table.commonCtrlProperty)
        expect(property.verticalOffset) == 1000
        expect(property.horizontalOffset) == 2000
    }
}

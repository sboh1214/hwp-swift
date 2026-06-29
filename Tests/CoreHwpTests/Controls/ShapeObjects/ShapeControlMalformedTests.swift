@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ShapeControlMalformedTests: XCTestCase {
    func testShapeControlRejectsInvalidCommonControlIdWithTypedError() {
        let rawCtrlId = UInt32.max
        let record = HwpRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: littleEndianData(rawCtrlId)
        )

        expect {
            _ = try HwpShapeControl.load(record)
        }.to(throwError { error in
            guard case let HwpError.invalidCtrlId(ctrlId) = error else {
                return fail("Expected invalidCtrlId, got \(error)")
            }
            expect(ctrlId) == rawCtrlId
        })
    }
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

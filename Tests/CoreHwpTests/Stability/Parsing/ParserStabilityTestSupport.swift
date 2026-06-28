@testable import CoreHwp
import Foundation

func expectedTopLevelSectionUnknownRecord() -> HwpUnknownRecord {
    expectedTestUnknownRecord(tagId: 0x2FE, level: 0, payload: Data([0xCA, 0xFE]), children: [
        expectedTestRecord(tagId: 0x2FD, level: 1, payload: Data([0xAA])),
    ])
}

func expectedSectionDefUnknownChildren() -> [HwpUnknownRecord] {
    [
        expectedSectionDefUnknownChild(.footnoteShape, Data([0xF0])),
        expectedSectionDefUnknownChild(.pageBorderFill, Data([0xB0])),
        expectedTestUnknownRecord(tagId: 0x2FE, level: 2, payload: Data([0xCA, 0xFE])),
    ]
}

private func expectedSectionDefUnknownChild(
    _ tag: HwpSectionTag,
    _ payload: Data
) -> HwpUnknownRecord {
    expectedTestUnknownRecord(tagId: tag.rawValue, level: 2, payload: payload)
}

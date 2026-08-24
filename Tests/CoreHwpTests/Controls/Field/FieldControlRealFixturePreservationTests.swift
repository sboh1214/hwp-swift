@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class FieldControlRealFixturePreservationTests: XCTestCase {
    func testMemoFixtureUnknownFieldParameterIsClassifiedAsMemoControl() throws {
        let hwp = try openHwp(#file, "memo")
        let memo = try memoFieldControl(in: hwp)

        assertMemoFixtureFieldControl(memo)
    }
}

private func memoFieldControl(in hwp: HwpFile) throws -> HwpFieldControl {
    guard let memo = FixtureDerivedValues
        .fieldControls(from: hwp)
        .first(where: { $0.semanticKind == .memo })
    else {
        fail("Expected memo fixture to contain memo field control")
        throw HwpError.recordDoesNotExist(tag: HwpSectionTag.ctrlHeader.rawValue)
    }

    return memo
}

private func assertMemoFixtureFieldControl(_ memo: HwpFieldControl) {
    let parameter = "MEMO/65535/1/239261456/31259664/sboh/\\;;"

    expect(memo.ctrlId) == .unknown
    expect(memo.semanticKind) == .memo
    expect(memo.isMemoField) == true
    expect(memo.isRevisionField) == false
    assertMemoFixtureTypedFieldHeader(memo, parameter)
    expect(memo.fieldParameterHeaderValue) == 0x8001
    expect(memo.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
    expect(memo.fieldParameterCharacterCount) == parameter.utf16.count
    expect(memo.fieldParameterLengthRawPayload) == Data([40, 0])
    expect(memo.fieldParameter) == parameter
    expect(memo.fieldParameterRawPayload?.count) == 80
    expect(Array(memo.fieldParameterRawPayload?.prefix(8) ?? Data())) == [
        77, 0, 69, 0, 77, 0, 79, 0,
    ]
    expect(Array(memo.fieldParameterRawPayload?.suffix(8) ?? Data())) == [
        47, 0, 92, 0, 59, 0, 59, 0,
    ]
    expect(memo.fieldParameterRawTrailing) == Data(memo.rawTrailing.dropFirst(87))
    expect(memo.fieldParameterRawTrailing?.count) == 8
    expect(memo.memoParameter?.rawValue) == parameter
    expect(memo.memoParameter?.rawPayload) == memo.fieldParameterRawPayload
    expect(memo.memoParameter?.marker) == "MEMO"
    expect(memo.memoParameter?.components) == [
        "MEMO", "65535", "1", "239261456", "31259664", "sboh", "\\;;",
    ]
    expect(memo.memoParameter?.fields) == [
        "65535", "1", "239261456", "31259664", "sboh", "\\;;",
    ]
    expect(memo.memoParameter?.author) == "sboh"
    expect(memo.memoParameter?.rawTrailing) == memo.fieldParameterRawTrailing
    expect(memo.rawPayload.count) == 99
    expect(Array(memo.rawPayload.prefix(8))) == [107, 110, 117, 37, 1, 128, 0, 0]
    expect(Array(memo.rawPayload.suffix(8))) == [140, 64, 121, 66, 1, 0, 0, 0]
    expect(memo.rawTrailing.count) == 95
    expect(Array(memo.rawTrailing.prefix(8))) == [1, 128, 0, 0, 0, 40, 0, 77]
    expect(Array(memo.rawTrailing.suffix(8))) == [140, 64, 121, 66, 1, 0, 0, 0]
    expect(memo.unknownChildren).to(beEmpty())
}

private func assertMemoFixtureTypedFieldHeader(
    _ memo: HwpFieldControl,
    _ parameter: String
) {
    expect(memo.properties) == 0x8001
    expect(memo.propertiesRawPayload) == Data([1, 128, 0, 0])
    expect(memo.propertyInfo?.rawValue) == 0x8001
    expect(memo.propertyInfo?.isInitialState) == false
    expect(memo.extraProperties) == 0
    expect(memo.extraPropertiesRawPayload) == Data([0])
    expect(memo.commandCharacterCount) == parameter.utf16.count
    expect(memo.commandLengthRawPayload) == Data([40, 0])
    expect(memo.command) == parameter
    expect(memo.commandRawPayload?.count) == 80
    expect(Array(memo.commandRawPayload?.prefix(8) ?? Data())) == [
        77, 0, 69, 0, 77, 0, 79, 0,
    ]
    expect(Array(memo.commandRawPayload?.suffix(8) ?? Data())) == [
        47, 0, 92, 0, 59, 0, 59, 0,
    ]
    expect(memo.commandRawTrailing) == Data(memo.rawTrailing.dropFirst(87))
    expect(memo.commandRawTrailing?.count) == 8
    expect(memo.fieldId) == 0x4279_408C
    expect(memo.fieldIdRawPayload) == Data([140, 64, 121, 66])
    expect(memo.memoIndex) == 1
    expect(memo.memoIndexRawPayload) == Data([1, 0, 0, 0])
}

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

    func testMemoFixtureUnknownFieldParameterSurvivesCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "memo")
        let memo = try memoFieldControl(in: hwp)
        let encoded = try JSONEncoder().encode(HwpCtrlId.memo(memo))
        let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)

        guard case let .memo(roundTripped) = decoded else {
            return fail("Expected memo control after Codable round-trip")
        }

        assertMemoFixtureFieldControl(roundTripped)
    }

    func testMemoFixtureFieldControlSurvivesHwpFileCodableRoundTrip() throws {
        let fixture = try FixtureLoader.load(id: "memo")
        let hwp = try HwpFile(fromPath: fixture.documentURL.path)
        let decoded = try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
        let originalMemo = try memoFieldControl(in: hwp)
        let memo = try memoFieldControl(in: decoded)

        FixtureAssertions.assertFieldControls(
            fixture.manifest.expectations.fieldControls ?? [],
            decoded
        )
        assertMemoFixtureFieldControl(memo)
        assertMemoFieldPayloadsMatch(memo, originalMemo)
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
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
    expect(memo.fieldParameterHeaderValue) == 0x8001
    expect(memo.fieldParameterHeaderRawPayload) == Data([1, 128, 0, 0])
    expect(memo.fieldParameterCharacterCount) == parameter.utf16.count
    expect(memo.fieldParameterLengthRawPayload) == Data([0, 40])
    expect(memo.fieldParameter) == parameter
    expect(memo.fieldParameterRawPayload?.count) == 80
    expect(Array(memo.fieldParameterRawPayload?.prefix(8) ?? Data())) == [
        0, 77, 0, 69, 0, 77, 0, 79,
    ]
    expect(Array(memo.fieldParameterRawPayload?.suffix(8) ?? Data())) == [
        0, 47, 0, 92, 0, 59, 0, 59,
    ]
    expect(memo.fieldParameterRawTrailing) == Data(memo.rawTrailing.dropFirst(86))
    expect(memo.fieldParameterRawTrailing?.count) == 9
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

private func assertMemoFieldPayloadsMatch(_ decoded: HwpFieldControl, _ original: HwpFieldControl) {
    expect(decoded.ctrlId) == original.ctrlId
    expect(decoded.semanticKind) == original.semanticKind
    expect(decoded.fieldParameterHeaderValue) == original.fieldParameterHeaderValue
    expect(decoded.fieldParameterHeaderRawPayload) == original.fieldParameterHeaderRawPayload
    expect(decoded.fieldParameterCharacterCount) == original.fieldParameterCharacterCount
    expect(decoded.fieldParameterLengthRawPayload) == original.fieldParameterLengthRawPayload
    expect(decoded.fieldParameter) == original.fieldParameter
    expect(decoded.fieldParameterRawPayload) == original.fieldParameterRawPayload
    expect(decoded.fieldParameterRawTrailing) == original.fieldParameterRawTrailing
    expect(decoded.memoParameter) == original.memoParameter
    expect(decoded.rawPayload) == original.rawPayload
    expect(decoded.rawTrailing) == original.rawTrailing
    expect(decoded.unknownChildren) == original.unknownChildren
}

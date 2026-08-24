@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `HwpParaText.wcharCount` O(1) 저장값 전환 회귀 (#67).
///
/// 파스 루프 누적값이 종전 reduce 계산과 같아야 하고, charArray 변경 시
/// didSet으로 재동기화된다.
final class ParaTextWcharCountTests: XCTestCase {
    func testParsedWcharCountMatchesLegacyReduceForMixedControlChars() throws {
        // 순수 문자 1 + inline 컨트롤(4) 8 + extended 컨트롤(2) 8 = 17 wchar.
        var payload = wcharLittleEndianData(WCHAR(0xAC00))
        payload.append(wcharLittleEndianData(WCHAR(4)))
        payload.append(Data(repeating: 0xAA, count: 14))
        payload.append(wcharLittleEndianData(WCHAR(2)))
        payload.append(Data(repeating: 0xBB, count: 14))

        let paraText = try HwpParaText.load(payload)

        expect(paraText.wcharCount) == 17
        expect(paraText.wcharCount) == legacyReduceWcharCount(paraText.charArray)
        expect(paraText.charArray.count) == 3
    }

    func testWcharCountResynchronizesWhenCharArrayIsMutated() throws {
        var paraText = try HwpParaText.load(wcharLittleEndianData(WCHAR(0xAC00)))
        expect(paraText.wcharCount) == 1

        paraText.charArray.append(HwpChar(type: .char, value: 65))
        expect(paraText.wcharCount) == 2

        paraText.charArray.append(
            HwpChar(type: .inline, value: 4, payload: Data(repeating: 0, count: 14))
        )
        expect(paraText.wcharCount) == 10

        paraText.charArray = []
        expect(paraText.wcharCount) == 0
    }

    func testDefaultParaTextKeepsBlankDocumentCount() {
        // 기본 문단(extended 2·2 + char 13, payload 없음)은 종전 계산대로 3.
        expect(HwpParaText().wcharCount) == 3
    }
}

private func legacyReduceWcharCount(_ charArray: [HwpChar]) -> Int {
    charArray.reduce(0) { $0 + ($1.payload == nil ? 1 : 8) }
}

private func wcharLittleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

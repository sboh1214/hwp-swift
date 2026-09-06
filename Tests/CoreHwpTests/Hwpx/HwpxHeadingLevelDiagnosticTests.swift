@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `hh:heading@level`이 표 44의 3비트 밖일 때의 강등 (#153).
///
/// `HwpxHeaderDiagnosticsTests`(type_body_length 상한 근처)에 얹지 않고 따로 둔다.
final class HwpxHeadingLevelDiagnosticTests: XCTestCase {
    /// 3비트에 담기지 않는 `hh:heading@level`(9·10수준)은 머리 종류 없음으로 접고
    /// 진단으로 남긴다 — 그대로 `& 0b111`로 접으면 9수준이 1수준으로 읽혀 번호 생성이
    /// 틀린 라벨을 만든다. 담기는 8수준(저장값 7)은 그대로다.
    func testHeadingLevelsBeyondThreeBitsAreDemotedIntoDiagnostics() throws {
        let xml = HwpxHeaderFixture.headerXML
            .replacingOccurrences(
                of: "<hh:heading type=\"OUTLINE\" idRef=\"0\" level=\"2\"/>",
                with: "<hh:heading type=\"OUTLINE\" idRef=\"0\" level=\"9\"/>"
            )
            .replacingOccurrences(
                of: "<hh:paraPr id=\"9\"><hh:align horizontal=\"JUSTIFY\"/>",
                with: "<hh:paraPr id=\"9\"><hh:align horizontal=\"JUSTIFY\"/>"
                    + "<hh:heading type=\"NUMBER\" idRef=\"1\" level=\"7\"/>"
            )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(xml)
        let paraShapes = docInfo.idMappings.paraShapeArray

        expect(paraShapes[0].property1Info.headingTypeRawValue) == 0
        expect(paraShapes[0].property1Info.headingLevelRawValue) == 0
        expect(paraShapes[1].property1Info.headingTypeRawValue) == 2
        expect(paraShapes[1].property1Info.headingLevelRawValue) == 7
        let payloads = docInfo.unknownRecords.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }
        expect(payloads.filter { $0.hasPrefix("heading@level=") }) == ["heading@level=9"]
        // 머리 종류 없음의 수준은 접지 않고 진단도 내지 않는다.
        let none = xml.replacingOccurrences(
            of: "<hh:heading type=\"OUTLINE\" idRef=\"0\" level=\"9\"/>",
            with: "<hh:heading type=\"NONE\" idRef=\"0\" level=\"9\"/>"
        )
        let (plain, _) = try HwpxHeaderFixture.mapHeader(none)
        expect(plain.unknownRecords.contains { $0.payload.starts(with: Data("heading@".utf8)) })
            == false
    }
}

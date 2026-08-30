@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 구역·secPr·lineseg 매핑의 구조 불변식 — 조작·불완전 입력이 조판 전제를
/// 조용히 어기지 않는지 고정한다.
final class HwpxSectionInvariantTests: XCTestCase {
    private func parse(_ xml: String) throws -> HwpxXMLNode {
        try HwpxXMLTreeParser.parse(Data(xml.utf8), entry: "Contents/section0.xml")
    }

    func testSectionWhoseFirstParagraphLacksSecPrIsRejected() {
        // 문단은 파싱되지만 첫 문단에 secPr가 없다 — 그대로 받으면 paginator가
        // 구역 경계를 인식하지 못해 앞 구역의 기하로 조판된다.
        let body = "<hp:p id=\"1\" paraPrIDRef=\"0\" styleIDRef=\"0\">"
            + "<hp:run charPrIDRef=\"7\"><hp:t>가</hp:t></hp:run></hp:p>"
        expect {
            _ = try HwpxSectionFixture.mapSection(body)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("secPr"))
        })
    }

    func testLineCacheMissingGeometryAttributeDegradesToReflow() throws {
        // vertsize 부재 — 0을 합성하면 높이 0 줄이 절대 조판에 채택된다.
        // 대조군: 속성이 온전한 blankBody 캐시는 채택된다.
        let clean = try HwpxSectionFixture.mapSection(HwpxSectionFixture.blankBody)
        expect(clean.paragraph[0].paraLineSeg.paraLineSegInternalArray.count) == 1

        let degraded = try HwpxSectionFixture.mapSection(
            HwpxSectionFixture.blankBody.replacingOccurrences(
                of: " vertsize=\"1000\"", with: ""
            )
        )
        expect(degraded.paragraph[0].paraLineSeg.paraLineSegInternalArray).to(beEmpty())
    }
}

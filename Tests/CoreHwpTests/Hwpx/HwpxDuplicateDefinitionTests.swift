@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 같은 자리가 두 번 선언됐을 때의 계약 — **첫 등장만 소비하고 나머지는
/// 진단에 남긴다** (바이너리 `HwpDocInfo`의 singleton 슬롯과 같은 계열).
/// 잎 층위는 각 매퍼 스위트가, 가족·파트 층위는 여기가 잠근다.
final class HwpxDuplicateDefinitionTests: XCTestCase {
    /// 진단 레코드를 자손까지 펼친 이름 목록 — 강등은 서브트리째 실리므로
    /// 최상위만 훑으면 둘째 래퍼 안의 미지 요소를 못 본다.
    private static func flatNames(_ records: [HwpUnknownRecord]) -> [String] {
        records.flatMap { record -> [String] in
            [String(bytes: record.payload, encoding: .utf8) ?? ""]
                + flatNames(record.children)
        }
    }

    func testDuplicateDefinitionFamilyKeepsTheFirstAndDemotesTheRest() throws {
        // 배열은 대입이라 마지막 가족이 이기는데 id 테이블은 첫 등장이 이긴다
        // — 그대로 두면 첫 가족의 id가 두 번째 가족의 정의로 해석돼 문단
        // 서식이 조용히 바뀐다 (실측: id 7이 20pt 이탤릭으로 조판됐다).
        let withDuplicate = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:tabProperties itemCnt=\"2\">",
            with: "<hh:charProperties itemCnt=\"1\">"
                + "<hh:charPr id=\"91\" height=\"2000\" textColor=\"#000000\" "
                + "borderFillIDRef=\"1\"><hh:italic/></hh:charPr>"
                + "</hh:charProperties>"
                + "<hh:tabProperties itemCnt=\"2\">"
        )
        let (docInfo, tables) = try HwpxHeaderFixture.mapHeader(withDuplicate)

        // 첫 가족이 그대로 남는다 — 두 번째 가족의 1개짜리 배열이 아니다.
        expect(docInfo.idMappings.charShapeArray.count) == 2
        expect(docInfo.idMappings.charShapeArray[0].baseSize) == 1000
        expect(docInfo.idMappings.charShapeArray[0].property.isItalic) == false
        // 두 번째 가족의 id는 등록되지 않는다 — 첫 가족의 오프셋 공간을
        // 침범하면 서로 다른 id가 같은 슬롯을 가리킨다.
        expect(tables.charShape.offset(of: "91")).to(beNil())
        expect(tables.charShape.offset(of: "7")) == 0
        // 버려진 가족은 진단에 남는다 (조용한 유실 금지).
        expect(Self.flatNames(docInfo.unknownRecords)).to(contain("charProperties"))
    }

    func testDuplicateBeginNumIsDemotedInsteadOfOverwriting() throws {
        // 두 번째부터 적용하면 마지막이 이겨 앞선 선언이 조용히 덮인다.
        let withDuplicate = HwpxHeaderFixture.headerXML.replacingOccurrences(
            of: "<hh:refList>",
            with: "<hh:beginNum page=\"9\" footnote=\"1\" endnote=\"1\" "
                + "pic=\"1\" tbl=\"1\" equation=\"1\"/><hh:refList>"
        )
        let (docInfo, _) = try HwpxHeaderFixture.mapHeader(withDuplicate)

        expect(docInfo.documentProperties.startingIndex.page) == 3
        expect(Self.flatNames(docInfo.unknownRecords)).to(contain("beginNum"))
    }

    func testDuplicatePictureWrappersAreDemotedWithTheirDescendants() throws {
        // pic 레벨 소비는 이름 멤버십이라 둘째 래퍼가 통째로 사라진다 —
        // 그 안의 미지 요소까지 함께 사라져 그림이 완전한 파스로 보고된다.
        let withDuplicates = HwpxObjectFixture.pictureXML
            .replacingOccurrences(
                of: "<hp:imgClip left=\"10\"",
                with: "<hp:sz width=\"1\" height=\"1\"><hp:ghostSize/></hp:sz>"
                    + "<hp:imgClip left=\"10\""
            )
            .replacingOccurrences(
                of: "</hp:pic>",
                with: "<hc:img binaryItemIDRef=\"image1\" bright=\"9\">"
                    + "<hp:ghostImage/></hc:img></hp:pic>"
            )
        let control = HwpxPictureMapper.map(
            try HwpxObjectFixture.parse(withDuplicates),
            context: HwpxObjectFixture.makeContext(binItemIds: ["image1": 3])
        )

        let names = Self.flatNames(control.unknownChildren)
        expect(names).to(contain("sz"))
        expect(names).to(contain("ghostSize"))
        expect(names).to(contain("img"))
        expect(names).to(contain("ghostImage"))
        // 첫 등장은 그대로 모델에 실린다 (음성 대조).
        expect(try XCTUnwrap(control.commonCtrlProperty).width) == 21000
    }
}

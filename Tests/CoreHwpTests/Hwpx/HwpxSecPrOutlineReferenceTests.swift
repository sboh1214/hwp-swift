@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `hp:secPr@outlineShapeIDRef` → `HwpSectionDef.numberParaShapeId` (#152) —
/// 정상·생략·잘못된 참조 세 경로를 합성 XML로 고정한다. 실물 쌍의 대조는
/// `HwpxHwpEquivalenceTests`의 구역별 개요 번호 참조 축이 한다.
final class HwpxSecPrOutlineReferenceTests: XCTestCase {
    private func firstSectionDef(of section: HwpSection) throws -> HwpSectionDef {
        let ctrls = try XCTUnwrap(section.paragraph[0].ctrlHeaderArray)
        for ctrl in ctrls {
            if case let .section(sectionDef) = ctrl {
                return sectionDef
            }
        }
        struct MissingSectionDef: Error {}
        throw MissingSectionDef()
    }

    private func referenceDiagnostics(of sectionDef: HwpSectionDef) -> [String] {
        sectionDef.unknownChildren.compactMap {
            String(bytes: $0.payload, encoding: .utf8)
        }.filter { $0.hasPrefix(HwpxSecPrMapper.outlineReferenceDiagnosticPrefix) }
    }

    private func withOutlineRef(_ value: String?) -> String {
        let attribute = value.map { " outlineShapeIDRef=\"\($0)\"" } ?? ""
        return HwpxSectionFixture.blankBody.replacingOccurrences(
            of: "<hp:secPr id=\"\"", with: "<hp:secPr id=\"\"\(attribute)"
        )
    }

    /// 정상 참조는 id 테이블 오프셋 + 1이다 — HWPX id를 숫자 그대로 쓰지 않는다.
    func testResolvedReferenceBecomesOneBasedNumberingId() throws {
        let section = try HwpxSectionFixture.mapSection(withOutlineRef("2"))
        let sectionDef = try firstSectionDef(of: section)

        expect(sectionDef.numberParaShapeId) == 2
        expect(self.referenceDiagnostics(of: sectionDef)).to(beEmpty())

        let first = try firstSectionDef(of: HwpxSectionFixture.mapSection(withOutlineRef("1")))
        expect(first.numberParaShapeId) == 1
    }

    /// 생략은 0(참조 없음)이다 — 한컴 참조 모델의 생성자 초기값이고, 빈 문서
    /// 기본값 1을 지어내지 않는다. 진단도 없다.
    func testOmittedReferenceIsZeroWithoutDiagnostic() throws {
        let sectionDef = try firstSectionDef(of: HwpxSectionFixture.mapSection(withOutlineRef(nil)))

        expect(sectionDef.numberParaShapeId) == 0
        expect(self.referenceDiagnostics(of: sectionDef)).to(beEmpty())
        // 대조군 — 바이너리 빈 문서 기본값은 1이라 생략과 구분된다.
        expect(HwpSectionDef().numberParaShapeId) == 1
    }

    /// 잘못된 참조(테이블에 없는 id)는 0으로 접되 진단 레코드를 남겨 생략과
    /// 구분한다 — 다른 강등 자식(미소비 요소)과 같은 `unknownChildren` 채널이다.
    func testDanglingReferenceFallsBackToZeroWithDiagnostic() throws {
        for ref in ["9", "", "abc"] {
            let section = try HwpxSectionFixture.mapSection(withOutlineRef(ref))
            let sectionDef = try firstSectionDef(of: section)
            expect(sectionDef.numberParaShapeId).to(equal(0), description: "ref=\(ref)")
            expect(self.referenceDiagnostics(of: sectionDef)).to(
                equal(["secPr@outlineShapeIDRef=\(ref)"]), description: "ref=\(ref)"
            )
            expect(sectionDef.unknownChildren.map(\.tagId)).to(
                contain(hwpxSyntheticTagId), description: "ref=\(ref)"
            )
        }
    }

    /// 종단 — 헤더의 `hh:numbering` id 공간과 구역의 참조가 `HwpFile`에서 만난다.
    /// 잘못된 참조는 `parseDiagnostics()`에 합성 tagId(0) 레코드로 드러난다.
    func testFileLevelReferenceResolvesThroughHeaderIdTable() throws {
        func archive(headerNumberingId: String, sectionRef: String) -> Data {
            let header = HwpxArchiveFixture.headerXML.replacingOccurrences(
                of: "</hh:refList>",
                with: "<hh:numberings itemCnt=\"1\"><hh:numbering id=\"\(headerNumberingId)\"/>"
                    + "</hh:numberings></hh:refList>"
            )
            let section = HwpxArchiveFixture.sectionXML.replacingOccurrences(
                of: "<hp:secPr id=\"\"",
                with: "<hp:secPr id=\"\" outlineShapeIDRef=\"\(sectionRef)\""
            )
            var builder = ZipBuilder()
            builder.entries = [
                .init(name: "mimetype", content: Data("application/hwp+zip".utf8), method: 0),
                .init(
                    name: "version.xml",
                    content: Data(HwpxArchiveFixture.versionXML.utf8), method: 8
                ),
                .init(
                    name: "Contents/content.hpf",
                    content: Data(HwpxArchiveFixture.manifestXML.utf8), method: 8
                ),
                .init(name: "Contents/header.xml", content: Data(header.utf8), method: 8),
                .init(name: "Contents/section0.xml", content: Data(section.utf8), method: 8),
            ]
            return builder.build()
        }

        let resolved = try HwpFile(fromData: archive(headerNumberingId: "5", sectionRef: "5"))
        expect(try self.firstSectionDef(of: resolved.sectionArray[0]).numberParaShapeId) == 1
        expect(resolved.parseDiagnostics().contains {
            $0.kind == .unknownRecord && $0.tagId == hwpxSyntheticTagId
        }) == false

        let dangling = try HwpFile(fromData: archive(headerNumberingId: "5", sectionRef: "6"))
        expect(try self.firstSectionDef(of: dangling.sectionArray[0]).numberParaShapeId) == 0
        let diagnostics = dangling.parseDiagnostics().filter {
            $0.kind == .unknownRecord && $0.tagId == hwpxSyntheticTagId
        }
        expect(diagnostics.count) == 1
        expect(diagnostics.first?.path).to(contain("section[0].paragraph[0]"))
    }
}

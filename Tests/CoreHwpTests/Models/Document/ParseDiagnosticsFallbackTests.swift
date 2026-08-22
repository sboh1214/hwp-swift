@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `HwpFile.parseDiagnostics()` (#66) — 제네릭 raw 래퍼로 떨어진 승격 실패의 보고.
///
/// `HwpCtrlId.notImplemented`로 떨어지는 표·도형과 달리, 전용 파서가 있는
/// other/field 계열은 승격에 실패하면 `.other`/`.field`라는 **제네릭 래퍼**로
/// 보존된다 (`HwpParagraph`의 `columnOrOther`·`listControlOrOther`·
/// `hyperLinkOrField` 등). 그 래퍼에도 진단이 붙는지, 그리고 같은 래퍼가
/// **제자리인** 컨트롤에는 붙지 않는지를 짝으로 고정한다 — 음성 대조군이
/// 없으면 "래퍼면 무조건 보고"라는 오탐 구현도 통과한다.
final class ParseDiagnosticsFallbackTests: XCTestCase {
    // MARK: - other 계열: 전용 파서 실패 → .other

    func testColumnPromotionFailureReportsNotImplementedControl() throws {
        try expectFallbackDiagnostic(ctrlId: HwpOtherCtrlId.column.rawValue)
    }

    func testSectionDefPromotionFailureReportsNotImplementedControl() throws {
        // PAGE_DEF(73)를 아예 빼면 `recordDoesNotExist`가 되는데 그것은
        // `canFallbackToRawControl` 밖이라 폴백이 아니라 전파된다 — 절단한
        // 자식으로 `truncatedData`를 유도해야 폴백 경로에 닿는다.
        try expectFallbackDiagnostic(
            ctrlId: HwpOtherCtrlId.section.rawValue,
            children: [(tagId: HwpSectionTag.pageDef.rawValue, payload: Data([0x01]))],
            additionalDiagnostics: [
                HwpParseDiagnostic(
                    kind: .unknownRecord,
                    tagId: HwpSectionTag.pageDef.rawValue,
                    path: "section[0].paragraph[0].ctrl[0].unknownChild[0]"
                ),
            ]
        )
    }

    func testPageNumberPositionPromotionFailureReportsNotImplementedControl() throws {
        try expectFallbackDiagnostic(ctrlId: HwpOtherCtrlId.pageNumberPosition.rawValue)
    }

    func testHeaderListControlPromotionFailureReportsNotImplementedControl() throws {
        try expectFallbackDiagnostic(ctrlId: HwpOtherCtrlId.header.rawValue)
    }

    func testFootnoteListControlPromotionFailureReportsNotImplementedControl() throws {
        try expectFallbackDiagnostic(ctrlId: HwpOtherCtrlId.footnote.rawValue)
    }

    // MARK: - field 계열: 하이퍼링크 승격 실패 → .field

    func testHyperlinkPromotionFailureReportsNotImplementedControl() throws {
        let hwp = try fallbackDocument(ctrlId: HwpFieldCtrlId.hyperLink.rawValue)

        // 전제: 정말 .field 래퍼로 떨어졌는가 (다른 경로를 보고 있으면 무의미)
        guard case .field = try XCTUnwrap(firstControl(of: hwp)) else {
            return fail("hyperLink 승격 실패는 .field 래퍼로 폴백해야 한다")
        }
        expect(hwp.parseDiagnostics()) == [
            HwpParseDiagnostic(
                kind: .notImplementedControl,
                ctrlId: HwpFieldCtrlId.hyperLink.rawValue,
                path: "section[0].paragraph[0].ctrl[0]"
            ),
        ]
    }

    // MARK: - 음성 대조군: 같은 래퍼가 제자리인 컨트롤은 보고하지 않는다

    func testGenuineOtherFamilyControlProducesNoControlDiagnostic() throws {
        // bookmark는 전용 파서가 없어 `otherControl`이 `.bookmark`로 분류한다 —
        // 승격 실패가 아니므로 진단이 없어야 한다.
        let hwp = try fallbackDocument(ctrlId: HwpOtherCtrlId.bookmark.rawValue)

        guard case .bookmark = try XCTUnwrap(firstControl(of: hwp)) else {
            return fail("bookmark는 .bookmark로 분류되어야 한다")
        }
        expect(hwp.parseDiagnostics()).to(beEmpty())
    }

    func testGenuineFieldControlProducesNoControlDiagnostic() throws {
        // clickHere는 전용 파서가 없어 `.field`가 제자리다 — 같은 래퍼지만
        // 하이퍼링크와 달리 승격 실패가 아니므로 진단이 없어야 한다.
        let hwp = try fallbackDocument(ctrlId: HwpFieldCtrlId.clickHere.rawValue)

        guard case .field = try XCTUnwrap(firstControl(of: hwp)) else {
            return fail("clickHere는 .field로 분류되어야 한다")
        }
        expect(hwp.parseDiagnostics()).to(beEmpty())
    }

    // MARK: - 폴백 진단은 자식 보존과 공존한다

    func testFallbackControlStillReportsPreservedChildren() throws {
        var data = diagnosticsRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: diagnosticsParaHeaderPayload()
        )
        data.append(diagnosticsRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: diagnosticsLittleEndianData(HwpOtherCtrlId.column.rawValue)
        ))
        data.append(diagnosticsRecord(tagId: 0x2FD, level: 2, payload: Data([0x07])))
        data.append(diagnosticsRecord(
            tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()
        ))

        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: diagnosticsDocInfoData(sectionSize: 1),
            sectionDataArray: [data]
        )

        expect(hwp.parseDiagnostics()) == [
            HwpParseDiagnostic(
                kind: .notImplementedControl,
                ctrlId: HwpOtherCtrlId.column.rawValue,
                path: "section[0].paragraph[0].ctrl[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord,
                tagId: 0x2FD,
                path: "section[0].paragraph[0].ctrl[0].unknownChild[0]"
            ),
        ]
    }
}

private extension ParseDiagnosticsFallbackTests {
    /// ctrl id 4 byte만 담은 CTRL_HEADER 하나를 가진 최소 문서.
    /// 전용 파서는 뒤따르는 payload가 없어 `truncatedData` 등으로 실패하고,
    /// 제네릭 래퍼는 ctrl id만 읽으므로 성공한다.
    func fallbackDocument(
        ctrlId: UInt32,
        children: [(tagId: UInt32, payload: Data)] = []
    ) throws -> HwpFile {
        var data = diagnosticsRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: diagnosticsParaHeaderPayload()
        )
        data.append(diagnosticsRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: diagnosticsLittleEndianData(ctrlId)
        ))
        for child in children {
            data.append(diagnosticsRecord(tagId: child.tagId, level: 2, payload: child.payload))
        }
        data.append(diagnosticsRecord(
            tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()
        ))
        return try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: diagnosticsDocInfoData(sectionSize: 1),
            sectionDataArray: [data]
        )
    }

    func firstControl(of hwp: HwpFile) -> HwpCtrlId? {
        hwp.sectionArray.first?.paragraph.first?.ctrlHeaderArray?.first
    }

    /// other 계열 전용 파서의 승격 실패는 전부 `.other` 래퍼로 떨어진다.
    func expectFallbackDiagnostic(
        ctrlId: UInt32,
        children: [(tagId: UInt32, payload: Data)] = [],
        additionalDiagnostics: [HwpParseDiagnostic] = []
    ) throws {
        let hwp = try fallbackDocument(ctrlId: ctrlId, children: children)

        guard case .other = try XCTUnwrap(firstControl(of: hwp)) else {
            return fail("ctrlId \(ctrlId) 승격 실패는 .other 래퍼로 폴백해야 한다")
        }
        expect(hwp.parseDiagnostics()) == [
            HwpParseDiagnostic(
                kind: .notImplementedControl,
                ctrlId: ctrlId,
                path: "section[0].paragraph[0].ctrl[0]"
            ),
        ] + additionalDiagnostics
    }
}

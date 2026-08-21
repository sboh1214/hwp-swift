@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `HwpFile.parseDiagnostics()` (#66) — 미해석 요소 집계의 kind·path 계약.
///
/// 합성 스트림으로 unknown record/control의 위치 표기, 중첩 컨트롤(표 셀) 재귀,
/// raw 폴백(.notImplemented) 컨트롤, ViewText/BodyText의 path 분리,
/// `.default`/`.viewer` 두 모드의 진단 동일성을 고정한다. 복구 placeholder
/// 3층은 `ParseDiagnosticsRecoveryTests`가 잠근다. 합성 빌더는
/// `ParseDiagnosticsTestSupport.swift` 공용이다.
final class ParseDiagnosticsTests: XCTestCase {
    // MARK: - unknown record·control·child 재귀의 kind와 path

    func testUnknownRecordsControlsAndChildrenReportKindAndPath() throws {
        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: diagnosticsDocInfoData(sectionSize: 1, includeUnknownRecord: true),
            sectionDataArray: [diagnosticsUnknownHeavySectionData()]
        )

        expect(hwp.parseDiagnostics()) == [
            HwpParseDiagnostic(
                kind: .unknownRecord, tagId: 0x2F9, path: "docInfo.unknownRecord[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord, tagId: 0x2F8, path: "docInfo.unknownRecord[0].child[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord, tagId: 0x2FE, path: "section[0].unknownRecord[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord, tagId: 0x2FD, path: "section[0].unknownRecord[0].child[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord,
                tagId: 0x2FB,
                path: "section[0].paragraph[0].unknownChild[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord,
                tagId: 0x2FA,
                path: "section[0].paragraph[0].unknownChild[0].child[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownControl,
                ctrlId: 0x5858_5858,
                path: "section[0].paragraph[0].ctrl[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord,
                tagId: 0x2FC,
                path: "section[0].paragraph[0].ctrl[0].unknownChild[0]"
            ),
        ]
    }

    func testDefaultAndViewerModesProduceIdenticalDiagnostics() throws {
        // unknown record payload는 뷰어 모드에서도 비워지지 않고 분리 복사되므로
        // (`HwpUnknownRecord` 진단 시맨틱 보존) 두 모드의 진단은 같아야 한다.
        let docInfoData = diagnosticsDocInfoData(sectionSize: 1, includeUnknownRecord: true)
        let sectionData = diagnosticsUnknownHeavySectionData()

        let defaultDiagnostics = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: docInfoData,
            sectionDataArray: [sectionData]
        ).parseDiagnostics()
        let viewerDiagnostics = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: docInfoData,
            sectionDataArray: [sectionData],
            options: .viewer
        ).parseDiagnostics()

        expect(defaultDiagnostics).notTo(beEmpty())
        expect(viewerDiagnostics) == defaultDiagnostics
    }

    // MARK: - 중첩 표 셀 문단 재귀

    func testNestedTableUnknownsReportCellPaths() throws {
        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: diagnosticsDocInfoData(sectionSize: 1),
            sectionDataArray: [diagnosticsTableSectionData()]
        )

        expect(hwp.parseDiagnostics()) == [
            HwpParseDiagnostic(
                kind: .unknownRecord,
                tagId: 0x2FE,
                path: "section[0].paragraph[0].ctrl[0].unknownChild[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownControl,
                ctrlId: 0x5959_5959,
                path: "section[0].paragraph[0].ctrl[0].cell[0].paragraph[0].ctrl[0]"
            ),
        ]
    }

    func testNotImplementedControlFallbackReportsKindAndChildren() throws {
        // 알려진 ctrl id(표)지만 payload를 ctrl id 4 byte로 절단해 typed 파싱이
        // truncatedData로 실패하면 raw 폴백(.notImplemented)이 된다 — 이때
        // ctrl 전체가 미해석이므로 child record도 unknownChild로 나와야 한다.
        var data = diagnosticsRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: diagnosticsParaHeaderPayload()
        )
        data.append(diagnosticsRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 1,
            payload: diagnosticsLittleEndianData(HwpCommonCtrlId.table.rawValue)
        ))
        data.append(diagnosticsRecord(tagId: 0x2FD, level: 2, payload: Data([0x05])))
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
                ctrlId: HwpCommonCtrlId.table.rawValue,
                path: "section[0].paragraph[0].ctrl[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord,
                tagId: 0x2FD,
                path: "section[0].paragraph[0].ctrl[0].unknownChild[0]"
            ),
        ]
    }

    // MARK: - ViewText 표시본은 path 접두사로 갈린다

    func testViewTextDiagnosticsSplitByPathPrefix() throws {
        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: diagnosticsDocInfoData(sectionSize: 1),
            sectionDataArray: [diagnosticsSectionData(unknownTagId: 0x2FE)],
            viewTextData: [
                (name: "Section0", data: diagnosticsSectionData(unknownTagId: 0x2F0)),
            ]
        )

        expect(hwp.viewSectionArray.count) == 1
        expect(hwp.parseDiagnostics()) == [
            HwpParseDiagnostic(
                kind: .unknownRecord, tagId: 0x2FE, path: "section[0].unknownRecord[0]"
            ),
            HwpParseDiagnostic(
                kind: .unknownRecord, tagId: 0x2F0, path: "viewSection[0].unknownRecord[0]"
            ),
        ]
    }
}

@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `HwpFile.parseDiagnostics()` (#66) × 부분 복구 (#65) — 복구 placeholder
/// 3층(구역·문단·메모 문단)의 kind와 메모 그룹 path 인덱스를 고정한다.
/// 합성 빌더는 `ParseDiagnosticsTestSupport.swift` 공용이다.
final class ParseDiagnosticsRecoveryTests: XCTestCase {
    func testRecoveredPlaceholdersReportAllThreeLayers() throws {
        let sectionDataArray = [
            diagnosticsRecoverySectionData(),
            diagnosticsCorruptSectionData(),
        ]

        let recovered = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: diagnosticsDocInfoData(sectionSize: 2),
            sectionDataArray: sectionDataArray,
            options: .viewer
        )
        let diagnostics = recovered.parseDiagnostics()

        let recoveredDiagnostics = diagnostics.filter { $0.kind != .unknownRecord }
        expect(recoveredDiagnostics.map(\.kind)) == [
            .recoveredParagraph, .recoveredMemoParagraph, .recoveredSection,
        ]
        expect(recoveredDiagnostics.map(\.path)) == [
            "section[0].paragraph[1]",
            "section[0].paragraph[2].memo[0].paragraph[1]",
            "section[1]",
        ]
        expect(recoveredDiagnostics[0].detail).to(contain("char shape count mismatch"))
        expect(recoveredDiagnostics[1].detail).to(contain("char shape count mismatch"))
        expect(recoveredDiagnostics[2].detail).to(contain("record level 2 has no parent"))

        // placeholder는 원본 레코드를 unknownChildren로 보존하므로 (#65)
        // 같은 위치에 unknownRecord 진단이 따라 나온다 — 재파싱 근거 노출.
        expect(diagnostics).to(contain(HwpParseDiagnostic(
            kind: .unknownRecord,
            tagId: HwpSectionTag.paraHeader.rawValue,
            path: "section[0].paragraph[1].unknownChild[0]"
        )))
        expect(diagnostics).to(contain(HwpParseDiagnostic(
            kind: .unknownRecord,
            tagId: HwpSectionTag.paraCharShape.rawValue,
            path: "section[0].paragraph[1].unknownChild[0].child[0]"
        )))
        expect(diagnostics).to(contain(HwpParseDiagnostic(
            kind: .unknownRecord,
            tagId: HwpSectionTag.paraHeader.rawValue,
            path: "section[0].paragraph[2].memo[0].paragraph[1].unknownChild[0]"
        )))

        // 보존 모드 + 복구와 뷰어 모드(보존 off + 복구)의 진단은 같다.
        let preservingRecovered = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: diagnosticsDocInfoData(sectionSize: 2),
            sectionDataArray: sectionDataArray,
            options: HwpLoadOptions(recoverPartialContent: true)
        )
        expect(preservingRecovered.parseDiagnostics()) == diagnostics
    }

    func testMultipleMemoGroupsKeepGroupIndexInPath() throws {
        var host = diagnosticsRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 0,
            payload: diagnosticsParaHeaderPayload()
        )
        host.append(diagnosticsRecord(
            tagId: HwpSectionTag.paraCharShape.rawValue, level: 1, payload: Data()
        ))
        host.append(diagnosticsRecord(
            tagId: HwpSectionTag.memoList.rawValue, level: 1, payload: Data()
        ))
        host.append(diagnosticsMemoParagraphData(level: 1))
        host.append(diagnosticsRecord(
            tagId: HwpSectionTag.memoList.rawValue, level: 1, payload: Data()
        ))
        var secondMemoParagraph = diagnosticsRecord(
            tagId: HwpSectionTag.paraHeader.rawValue,
            level: 1,
            payload: diagnosticsParaHeaderPayload()
        )
        secondMemoParagraph.append(diagnosticsRecord(
            tagId: HwpSectionTag.ctrlHeader.rawValue,
            level: 2,
            payload: diagnosticsLittleEndianData(UInt32(0x5A5A_5A5A))
        ))
        secondMemoParagraph.append(diagnosticsRecord(
            tagId: HwpSectionTag.paraCharShape.rawValue, level: 2, payload: Data()
        ))
        host.append(secondMemoParagraph)

        let hwp = try HwpFile(
            fileHeader: HwpFileHeader(),
            docInfoData: diagnosticsDocInfoData(sectionSize: 1),
            sectionDataArray: [host]
        )

        expect(hwp.parseDiagnostics()) == [
            HwpParseDiagnostic(
                kind: .unknownControl,
                ctrlId: 0x5A5A_5A5A,
                path: "section[0].paragraph[0].memo[1].paragraph[0].ctrl[0]"
            ),
        ]
    }
}

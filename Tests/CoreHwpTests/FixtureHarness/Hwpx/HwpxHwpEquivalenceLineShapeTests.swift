@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 선 종류 축의 직접 핀 (#177) — `HwpxHwpEquivalenceTests`의 다른 축 핀과 같은
/// 규약이지만, 그 파일이 SwiftLint `file_length` 상한에 가까워 여기로 뗐다.
///
/// 실물은 한글 12.30.0이 같은 편집 세션에서 `.hwp`·`.hwpx`로 저장한 `line-shapes` 쌍이다:
/// 글자 아래 밑줄 17문단·취소선 17문단(각각 `LINETYPE2` 17종 순서), 17행 표(행마다
/// 네 방향 테두리를 같은 17종으로), 2단 + `DASH_DOT` 구분선, 각주 `DOT`·미주 `DASH`
/// 구분선. 등식만 두면 두 포맷이 함께 틀려도 통과하므로 HWPX 쪽 값을 HWP 저장본의
/// 비트로 못박는다.
final class HwpxHwpEquivalenceLineShapeTests: XCTestCase {
    private typealias Projection = DocumentEquivalenceProjection

    private func projections() throws -> (hwp: Projection, hwpx: Projection) {
        let hwp = try HwpFile(fromPath: FixtureLoader.load(id: "line-shapes").documentURL.path)
        let hwpx = try HwpFile(
            fromPath: HwpxFixtureLoader.load(id: "line-shapes").documentURL.path
        )
        return (Projection(of: hwp), Projection(of: hwpx))
    }

    /// 글자선 모양은 표 25 값(실선 0)이고 `LINETYPE2 - 1`이다. 마지막 `REV3D` 문단은
    /// 4비트를 넘쳐 한글이 실선 글자 모양으로 접었으므로 두 포맷 모두 0이다.
    func testLineShapesPairProjectsCharacterLineShapesOnBothFormats() throws {
        let (hwp, hwpx) = try projections()
        let expectedShapes = Array(0 ... 15) + [0]

        // 문단 0은 표제, 1-17 밑줄, 18-34 취소선, 35 표 앵커 문단.
        let underlineRuns = try hwpx.resolvedRunsByParagraph[1 ... 17]
            .map { try XCTUnwrap($0.first) }
        expect(underlineRuns.map(\.underlineType))
            == Array(repeating: HwpUnderlineType.under, count: 17)
        expect(underlineRuns.map(\.underlineShape)) == expectedShapes
        expect(underlineRuns.map(\.strikethrough)) == Array(repeating: 0, count: 17)

        let strikeoutRuns = try hwpx.resolvedRunsByParagraph[18 ... 34]
            .map { try XCTUnwrap($0.first) }
        expect(strikeoutRuns.map(\.strikethrough)) == Array(repeating: 1, count: 17)
        expect(strikeoutRuns.map(\.strikethroughShape)) == expectedShapes
        // 레거시 이중 기록(HWP: 글자 가운데 + 취소선 모양 복사)은 밑줄 없음·모양 0으로 접힌다.
        expect(strikeoutRuns.map(\.underlineType))
            == Array(repeating: HwpUnderlineType.none, count: 17)
        expect(strikeoutRuns.map(\.underlineShape)) == Array(repeating: 0, count: 17)

        expect(hwpx.resolvedRunsByParagraph) == hwp.resolvedRunsByParagraph
    }

    /// 테두리·대각선·단 구분선은 `LINETYPE2` 값 그대로다 (실선 1 · DOT 2 · DASH 3 · … · REV3D 17).
    func testLineShapesPairProjectsBorderAndDividerLinesOnBothFormats() throws {
        let (hwp, hwpx) = try projections()

        let cells = try hwpx.cellBorders.map { try XCTUnwrap($0) }
        expect(cells.count) == 17
        expect(cells.map(\.types)) == (1 ... 17).map { Array(repeating: UInt8($0), count: 4) }
        expect(cells.map(\.thicknesses)) == Array(repeating: [1, 1, 1, 1], count: 17)
        expect(cells.map(\.diagonalType)) == Array(repeating: 1, count: 17)
        expect(cells.map(\.diagonalThickness)) == Array(repeating: 0, count: 17)
        expect(hwpx.cellBorders) == hwp.cellBorders

        expect(hwpx.columnDividers) == [
            Projection.ColumnDivider(type: 4, thickness: 1, color: HwpColor(0, 0, 0)),
        ]
        expect(hwpx.columnDividers) == hwp.columnDividers

        // 각주 `DOT` → 2, 미주 `DASH` → 3 — 구분선도 테두리 축이다.
        expect(hwpx.noteShapes.map(\.dividerType)) == [2, 3]
        expect(hwpx.noteShapes) == hwp.noteShapes
    }
}

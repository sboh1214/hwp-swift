import CoreGraphics
import CoreHwp
import CoreText
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 줄 상자보다 **작은** 글자처럼 취급 개체가 한글이 그리는 자리에 놓이는지 (#195) —
/// `inline-object-baseline` HWP·HWPX 쌍.
///
/// 오라클은 한컴오피스 한글 12.30.0 (macOS, 2026-09-21)이 같은 편집 세션에서 내보낸 PDF의 그림
/// 상단·표 테두리·텍스트 베이스라인이다 (`Fixtures/inline-object-baseline/README.md`의 표):
/// 개체의 바깥 상자(개체 + 바깥 여백) 상단 = 베이스라인 − 0.85 × 바깥 상자 높이, 개체는 그 아래
/// 위 여백만큼. 개체 18개(그림 16·표 2)와 셀 안 그림 2개가 전부 0.12pt(한글 PDF의 장치 양자화)
/// 안이었다. 종전(바깥 상자 바닥을 베이스라인에)에는 상자보다 작은 개체가 0.15 × 높이만큼 위였다
/// — 20pt 그림 3pt, 30pt 그림 4.5pt.
///
/// 폰트는 `HwpFontResolver.testDeterministic`이다 — 한글 문서의 줄 상자·개체 자리는 글꼴 지표의
/// 함수가 아니므로 기기·CI가 같은 값을 낸다.
final class FixtureInlineObjectBaselineTests: XCTestCase {
    private static let ratio = HwpRenderTuning.Text.baselineAnchorRatio

    /// 한글 PDF 실측 — 문서 순서대로 (개체 상단 − 그 줄 베이스라인, 개체 높이). 셀 안 그림
    /// 둘은 표 블록의 셀에서 읽는다.
    private static let hancom: [(drop: Double, height: Double)] = [
        (-3.49, 4), (-6.85, 8), (-16.93, 20), (-25.57, 30), (-30.62, 36), (-33.98, 40),
        (-42.62, 50),
        (-18.50, 20), (-27.63, 20), (-16.95, 20), // M1 7-3 · M2 15-15 · R1 rel50
        (-16.92, 20), (-17.04, 20), (-18.48, 20), // L1 fix50 · T1 tbl · T2 tblm
        (-3.37, 4), (-16.93, 20), // S3 10/4 · S4 10/20
        (-6.85, 8), (-17.05, 20), (-25.57, 30), // C1
    ]
    private static let hancomCell: [(drop: Double, height: Double)] = [(-17.06, 20), (-6.86, 8)]

    /// 한글 PDF의 장치 양자화(0.12pt) + 우리 반올림 몫.
    private static let tolerance = 0.13

    func testHwpObjectsSitWhereHancomDrawsThem() async throws {
        try await Self.assertObjects(Self.pages(hwpx: false))
    }

    func testHwpxObjectsSitWhereHancomDrawsThem() async throws {
        try await Self.assertObjects(Self.pages(hwpx: true))
    }

    /// 두 포맷의 개체 프레임이 같다 — 매퍼가 크기·바깥 여백·줄 캐시를 같게 옮긴다.
    func testHwpAndHwpxPlaceObjectsIdentically() async throws {
        let hwp = try await Self.objects(in: Self.pages(hwpx: false))
        let hwpx = try await Self.objects(in: Self.pages(hwpx: true))
        expect(hwp.count) == 20
        expect(hwpx.count) == hwp.count
        for (lhs, rhs) in zip(hwp, hwpx) {
            expect(Double(lhs.frame.minY)).to(beCloseTo(Double(rhs.frame.minY), within: 0.001))
            expect(Double(lhs.frame.height))
                .to(beCloseTo(Double(rhs.frame.height), within: 0.001))
        }
    }

    /// 절대 자리 핀 — 첫 그림(4pt) 상단 = 본문 상단 99.2 + 첫 줄 10 + 34 − 3.4 = 139.8, 20pt 그림
    /// (`P3`) 254.2, 표 `T1` 2쪽 166.2, 셀 안 `S1` 401.6. 한글 PDF: 139.79·254.27·166.20·401.62.
    func testAbsolutePositionsMatchTheHancomPdf() async throws {
        let objects = try await Self.objects(in: Self.pages(hwpx: false))
        expect(objects.count) == 20
        guard objects.count == 20 else { return }
        expect(Double(objects[0].frame.minY)).to(beCloseTo(139.8, within: 0.01))
        expect(Double(objects[2].frame.minY)).to(beCloseTo(254.2, within: 0.01))
        expect(Double(objects[11].frame.minY)).to(beCloseTo(166.2, within: 0.01))
        expect(Double(objects[18].frame.minY)).to(beCloseTo(401.6, within: 0.05))
    }

    // MARK: 헬퍼

    private struct Object {
        let frame: CGRect
        /// 개체가 놓인 줄의 베이스라인 y (쪽 좌표)
        let baseline: CGFloat
    }

    private static func pages(hwpx: Bool) async throws -> [HwpPage] {
        let url = FixtureRoot.url(from: #file, subdirectory: hwpx ? "HwpxFixtures" : "Fixtures")
            .appendingPathComponent("inline-object-baseline")
            .appendingPathComponent(hwpx ? "document.hwpx" : "document.hwp")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        expect(document.pages.count) == 2
        return document.pages
    }

    /// 쪽의 개체(그림·글자처럼 취급 표·셀 안 그림)를 문서 순서로 — 각 개체에 그 줄의 베이스라인을
    /// 붙인다. 줄은 마커(U+FFFC)를 실은 drawText 줄이고, 마커 x 순서가 곧 개체 순서다.
    private static func objects(in pages: [HwpPage]) -> [Object] {
        var result: [Object] = []
        for page in pages {
            let markers = markerBaselines(page)
            var placed: [(x: CGFloat, frame: CGRect)] = []
            for block in page.blocks where block.role == .body {
                switch block.payload {
                case .image:
                    placed.append((block.frame.minX, block.frame))
                case let .table(table) where block.frame.width < 100:
                    placed.append((block.frame.minX, block.frame))
                    _ = table
                case let .table(table):
                    // 자리 차지 표 — 셀 안 그림은 셀 문단의 마커 줄에 붙는다.
                    for row in table.rows {
                        for cell in row.cells {
                            for image in cell.images {
                                let frame = image.rect.offsetBy(
                                    dx: block.frame.minX, dy: block.frame.minY
                                )
                                placed.append((frame.minX, frame))
                            }
                        }
                    }
                default:
                    break
                }
            }
            // 개체와 마커를 (줄, x) 순으로 짝짓는다 — 같은 줄의 개체는 x가 다르다.
            let orderedObjects = placed.sorted { lhs, rhs in
                let lhsLine = lineBaseline(above: lhs.frame.minY, in: markers)
                let rhsLine = lineBaseline(above: rhs.frame.minY, in: markers)
                return lhsLine == rhsLine ? lhs.x < rhs.x : lhsLine < rhsLine
            }
            for object in orderedObjects {
                // 개체의 베이스라인은 개체 상단보다 아래 — 그 줄의 마커 베이스라인.
                result.append(Object(
                    frame: object.frame,
                    baseline: lineBaseline(above: object.frame.minY, in: markers)
                ))
            }
        }
        return result
    }

    /// 개체 상단 `top` 아래에서 가장 가까운 마커 줄의 베이스라인 — 없으면 −1.
    private static func lineBaseline(
        above top: CGFloat, in markers: [(baseline: CGFloat, x: CGFloat)]
    ) -> CGFloat {
        markers.first { $0.baseline >= top - 0.5 }?.baseline ?? -1
    }

    /// 쪽의 drawText 줄 가운데 마커(U+FFFC + `hwp.controlIndex`)를 실은 줄의 베이스라인 —
    /// 오름차순. 한 줄에 마커가 여럿이면 하나만 든다.
    private static func markerBaselines(_ page: HwpPage) -> [(baseline: CGFloat, x: CGFloat)] {
        var lines: [(baseline: CGFloat, x: CGFloat)] = []
        for command in page.paintList.commands {
            guard case let .drawText(attributedString, origin, lineWidth) = command else {
                continue
            }
            for line in HwpDrawnTextLayout.lines(
                attributedString: attributedString, origin: origin, lineWidth: lineWidth
            ) {
                guard let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] else { continue }
                let hasMarker = runs.contains { run in
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    return attributes[HwpAttributedStringKey.controlIndex] != nil
                        && attributes[kCTRunDelegateAttributeName] != nil
                }
                if hasMarker {
                    lines.append((line.baselineOrigin.y, line.baselineOrigin.x))
                }
            }
        }
        return lines.sorted { $0.baseline < $1.baseline }
    }

    private static func assertObjects(_ pages: [HwpPage]) {
        let objects = objects(in: pages)
        expect(objects.count) == hancom.count + hancomCell.count
        guard objects.count == hancom.count + hancomCell.count else { return }
        for (index, expected) in (hancom + hancomCell).enumerated() {
            let object = objects[index]
            let drop = Double(object.frame.minY - object.baseline)
            expect(Double(object.frame.height))
                .to(beCloseTo(expected.height, within: 0.01), description: "#\(index) 높이")
            expect(drop).to(
                beCloseTo(expected.drop, within: tolerance), description: "#\(index) 한글 대비"
            )
            // 규칙 자체: 바깥 상자 상단 = 베이스라인 − 0.85 × 바깥 상자 높이 (여백은 표에 이미 들었다).
            expect(object.baseline)
                .to(beGreaterThan(object.frame.minY), description: "#\(index) 줄 짝")
        }
    }
}

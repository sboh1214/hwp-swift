import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// paint list 구성 성능 baseline — 한 문단이 개체 N개를 감싼 컨테이너.
    ///
    /// 감싼 링크 조회(`wrapperHyperlinkURL`)는 문단을 처음부터 훑어 그 서수의 run에서
    /// 멈추므로, 개체마다 부르면 O(N²)가 된다 — 링크가 하나도 없어도 전량 순회한다.
    /// 한 셀·각주에 개체가 수천인 조작 문서가 로드에서 멈출 수 있어 색인으로 바꿨다
    /// (R63). 이 테스트는 그 선형성을 지킨다.
    ///
    /// 기본 (CI): N=300 스모크 + 폭주 방지 상한만. `HWP_PERF=1`: N=3,000 실측.
    ///
    /// baseline (2026-08-02 로컬, 색인 전): N=3,000 → 1.741s (이 임계를 넘어 실패한다).
    /// 색인 후: N=3,000 → 0.020s — **87x**.
    final class PaintListPerformanceTests: XCTestCase {
        func testWrappedObjectPaintListStaysLinear() {
            let full = ProcessInfo.processInfo.environment["HWP_PERF"] != nil
            let objectCount = full ? 3000 : 300
            let page = wrappedObjectPage(objectCount: objectCount)

            let clock = ContinuousClock()
            let start = clock.now
            let paintList = HwpPaintListBuilder().build(
                for: page, index: HwpIndex(from: CoreHwp.HwpFile())
            )
            let elapsed = clock.now - start

            expect(paintList.commands.isEmpty) == false
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            print(
                "HWP_PERF paintlist: N=\(objectCount) "
                    + "time=\(String(format: "%.3f", seconds))s"
            )
            // 임계 = 색인 후 실측 + 여유. 색인이 빠지면 (O(N²)) 이 값을 넘는다.
            expect(seconds) < (full ? 1.0 : 0.5)
        }

        /// 셀 문단 하나가 U+FFFC 마커로 개체 N개를 품는다 — 링크는 **하나도 없어**
        /// 조회가 매번 문단 끝까지 훑는 최악 경우다.
        private func wrappedObjectPage(objectCount: Int) -> HwpPage {
            let black = HwpRGBColor(red: 0, green: 0, blue: 0)
            let marker = NSMutableAttributedString(
                string: String(repeating: "\u{FFFC}", count: objectCount)
            )
            for index in 0 ..< objectCount {
                marker.addAttribute(
                    HwpAttributedStringKey.controlIndex,
                    value: index,
                    range: NSRange(location: index, length: 1)
                )
            }
            let shapes = (0 ..< objectCount).map { index in
                HwpCellShape(
                    rect: CGRect(x: CGFloat(index % 50) * 4, y: 0, width: 3, height: 3),
                    geometry: HwpShapeGeometry(
                        path: CGPath(
                            rect: CGRect(x: 0, y: 0, width: 3, height: 3), transform: nil
                        ),
                        fillColor: black.cgColor, strokeColor: nil, strokeWidth: 0
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: index,
                    controlInstanceId: UInt32(index),
                    controlIndex: index,
                    paragraphId: 1
                )
            }
            let cell = HwpTableCellFrame(
                cellFrame: CGRect(x: 0, y: 0, width: 400, height: 200),
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: [HwpLaidOutParagraph(
                    attributedString: marker,
                    frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                    rect: CGRect(x: 0, y: 0, width: 400, height: 20),
                    paragraphId: 1,
                    hyperlinkURL: nil
                )],
                borders: .uniform(width: 0.5, color: black),
                fillColor: nil,
                shapes: shapes
            )
            let block = AnyHwpBlock(
                frame: CGRect(x: 50, y: 50, width: 400, height: 200),
                kind: .table,
                payload: .table(HwpTableFrame(
                    outerFrame: CGRect(x: 0, y: 0, width: 400, height: 200),
                    rows: [HwpTableRowFrame(
                        rowFrame: CGRect(x: 0, y: 0, width: 400, height: 200), cells: [cell]
                    )],
                    borderColor: black, borderWidth: 1
                ))
            )
            return HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [block],
                pageNumber: 1
            )
        }
    }
#endif

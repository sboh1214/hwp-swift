import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 컨테이너 개체 수집(`HwpParagraphObjectCollector.objects`)은 개체 요소 수에
    /// 비례해야 한다 (#158 리뷰). 글상자 문단의 번호 경로 서수를 요소마다
    /// `HwpNumberingScope.textboxChildOffset`으로 앞선 요소 전체를 다시 더해 구하면
    /// 요소 N개짜리 개체 하나가 O(N²)이 되고, 번호나 글상자가 없는 요소도 빈 리스트를
    /// 되풀이해 훑는다 — 리뷰 실측(디버그): 요소 1,000/2,000/4,000개가 0.126/0.492/1.896초.
    ///
    /// 기본 (CI): 요소 8,000개 스모크 + 폭주 방지 상한. `HWP_PERF=1`: 40,000개 실측.
    final class ObjectCollectorPerformanceTests: XCTestCase {
        func testCollectingManyComponentsIsLinearInComponentCount() throws {
            let full = ProcessInfo.processInfo.environment["HWP_PERF"] != nil
            let componentCount = full ? 40000 : 8000
            // 글상자·그림·세부 정보가 없는 요소 — 수집 자체는 아무것도 내지 않으므로
            // 남는 비용은 요소 반복문(접두 합 계산)뿐이다.
            var object = HwpSynthetic.inlineShapeObject(width: 1000, height: 1000)
            object.shapeComponentArray = Array(
                repeating: object.shapeComponentArray[0], count: componentCount
            )
            var paragraph = try HwpSynthetic.textParagraph("셀")
            paragraph.ctrlHeaderArray = [.genShapeObject(object)]
            let collector = HwpParagraphObjectCollector(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic,
                sizeResolver: nil,
                collectsTextboxes: true,
                attributeCache: nil
            )

            let clock = ContinuousClock()
            let start = clock.now
            let objects = collector.objects(
                in: paragraph,
                frame: HwpParagraphFrame(totalHeight: 16, lines: []),
                paragraphRect: CGRect(x: 0, y: 0, width: 400, height: 16)
            )
            let elapsed = clock.now - start
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            print(
                "HWP_PERF object collector: components=\(componentCount) "
                    + "time=\(String(format: "%.3f", seconds))s"
            )
            expect(objects.textboxes).to(beEmpty())
            expect(objects.images).to(beEmpty())
            // 실측(2026-09-07 로컬, 디버그): 8,000개 0.022s, 40,000개 0.111s. 요소마다 접두를
            // 다시 더하던 구현은 8,000개에 7.48초(이차 증가)였다.
            expect(seconds) < (full ? 3.0 : 1.5)
        }
    }
#endif

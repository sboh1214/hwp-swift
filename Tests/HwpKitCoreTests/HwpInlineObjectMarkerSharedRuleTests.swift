import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 개체 마커의 글자 모양을 줄 상자에서 빼는 규칙(#217)을 **줄 지표 밖에서** 다시 쓰는 판정들 —
    /// 절대 캐시의 낡음 판정, 단 구분선 끝의 마지막 줄 근사, 컨테이너 블록의 결합 문자열 구분자.
    /// 줄 지표(`HwpDrawnTextLayout.LineMetrics`)만 고치면 이 셋이 옛 규칙에 남아 한글이 막 저장한
    /// 캐시를 낡았다고 보거나 그려진 줄 상자와 어긋난다 (#217 리뷰). 규칙 자체와 실측 근거는
    /// `HwpInlineObjectMarkerLineBoxTests`.
    final class HwpInlineObjectMarkerSharedRuleTests: XCTestCase {
        private typealias Fixtures = LineBoxFixtures
        private typealias Lines = HwpInlineObjectMarkerLineBoxTests
        private static let percent160 = Fixtures.rule(.percent, 160)

        /// 절대 캐시의 낡음 판정은 줄 공간을 예약한 개체 마커의 글꼴 크기를 보지 않는다 — 한글이 막
        /// 저장한 K7 줄(10pt 글 + 40pt 마커의 8pt 그림, `vertsize` 1000)은 신선하다. 높이 0 마커
        /// (책갈피)의 40pt와 글자 자신의 40pt는 상자에 드는 크기라 10pt 캐시를 여전히 낡게 만든다.
        func testObjectMarkerSizeDoesNotMakeAFreshCacheStale() throws {
            let cache = try Self.lineCache(height: 1000)
            let text = Fixtures.attributes(size: 10)
            let object = NSMutableAttributedString(string: "ab", attributes: text)
            object.append(Lines.marker(height: 8, attributes: Fixtures.attributes(size: 40)))
            expect(Self.isStale(cache, object)) == false

            let bookmark = NSMutableAttributedString(string: "ab", attributes: text)
            bookmark.append(
                Lines.marker(height: 0, width: 0, attributes: Fixtures.attributes(size: 40))
            )
            expect(Self.isStale(cache, bookmark)) == true

            let large = NSAttributedString(string: "ab", attributes: Fixtures.attributes(size: 40))
            expect(Self.isStale(cache, large)) == true
        }

        /// 개체 마커의 글꼴을 빼도 문단 끝 글자(CR)의 크기는 본다 (#217 PR 리뷰) — 한글은 CR 크기를
        /// 마지막 줄 상자에 넣으므로(#206) 40pt 마커의 8pt 그림 + 40pt CR 문단(`O2` 꼴)의 신선한 캐시는
        /// 4000이고 1000은 낡았다. 마커를 빼면 그 40pt를 알려 주는 것은 CR뿐이다 — 안 보면 낡은 캐시를
        /// 믿어 그려지는 40pt 줄이 뒤 문단을 덮는다. CR이 10pt면 1000이 신선하고, 10pt 글 + 40pt CR도
        /// 1000이면 낡았다. 다음 쪽으로 이어지는 조각의 끝은 문단 끝이 아니라 CR을 보지 않는다.
        func testParagraphEndSizeStillMakesAShortCacheStale() throws {
            let short = try Self.lineCache(height: 1000)
            let objectOnly = Lines.marker(height: 8, attributes: Fixtures.attributes(size: 40))
            let bigEnd = Lines.withEndSize(40, objectOnly)
            expect(Self.isStale(short, bigEnd)) == true
            expect(Self.isStale(try Self.lineCache(height: 4000), bigEnd)) == false
            expect(Self.isStale(short, Lines.withEndSize(10, objectOnly))) == false

            let text = NSAttributedString(string: "ab", attributes: Fixtures.attributes(size: 10))
            expect(Self.isStale(short, Lines.withEndSize(40, text))) == true

            let continued = NSMutableAttributedString(attributedString: bigEnd)
            continued.addAttribute(
                HwpAttributedStringKey.continuedParagraphFragment, value: NSNumber(value: true),
                range: NSRange(location: 0, length: continued.length)
            )
            expect(Self.isStale(short, continued)) == false
        }

        /// 단 구분선 끝의 마지막 줄 근사도 끝 글자가 개체 마커면 줄 상자를 개체 높이·문단 끝 글자로
        /// 잡는다 — 10pt 글 + 40pt 마커의 8pt 그림 + 10pt 문단 끝(O1 꼴) 줄의 줄 간격 몫은 최소 12 →
        /// 2, 고정 30 → 20, 비율 160% → 24(여분은 마커 기준)이고 렌더가 그린 마지막 줄의 전진량 − 상자와
        /// 같다. 종전에는 마커의 40pt를 상자로 봐 최소·고정이 0이라 구분선이 그 줄 상자 아래로 2·20pt
        /// 뻗었다.
        func testColumnDividerApproximationUsesTheObjectBox() {
            let rows: [Fixtures.RuleCase<CGFloat>] = [
                .init(.atLeast, 12, 2), .init(.fixed, 30, 20), .init(.percent, 160, 24),
            ]
            for row in rows {
                let text = Fixtures.attributes(size: 10)
                let output = NSMutableAttributedString(string: "ab", attributes: text)
                output.append(Lines.marker(height: 8, attributes: Fixtures.attributes(size: 40)))
                let string = Lines.withEndSize(10, Fixtures.applying(row.rule, to: output))
                let box = HwpDrawnTextLayout.trailingLineBox(in: string)
                expect(box.line).to(equal(10), description: row.label)
                expect(box.text).to(equal(40), description: row.label)
                let spacing = HwpColumnBandController.measuredTrailingSpacing(of: string)
                expect(Double(spacing))
                    .to(beCloseTo(Double(row.expected), within: 0.001), description: row.label)
                let frame = Lines.measure(string, rule: row.rule)
                let rendered = frame.totalHeight - (frame.lines.last?.boxHeight ?? 0)
                expect(Double(spacing))
                    .to(beCloseTo(Double(rendered), within: 0.001), description: row.label)
            }
        }

        /// 컨테이너 블록이 문단들을 `\n`으로 이은 문자열(payload 없는 조각이 그대로 그린다)에서 앞
        /// 문단이 개체 마커로 끝나면 구분자는 마커가 아니라 문단 끝 글자의 크기를 싣는다 — 구분자는
        /// 글자로 조판되므로 마커의 40pt를 물려받으면 그 줄 상자가 다시 40이 된다. 첫 문단(10pt 글 +
        /// 40pt 마커의 8pt 그림, 문단 끝 10pt)의 줄은 문단 혼자일 때와 같이 상자 10·전진량 34다.
        func testCombinedBlockSeparatorAfterAnObjectMarkerTakesTheParagraphEndSize() {
            let text = Fixtures.attributes(size: 10)
            let first = NSMutableAttributedString(string: "ab", attributes: text)
            first.append(Lines.marker(height: 8, attributes: Fixtures.attributes(size: 40)))
            let second = NSAttributedString(string: "cd", attributes: text)
            let paragraphs = [
                Lines.withEndSize(10, Fixtures.applying(Self.percent160, to: first)),
                Lines.withEndSize(10, Fixtures.applying(Self.percent160, to: second)),
            ]
            guard let combined = HwpCombinedBlockString.combine(paragraphs) else {
                fail("결합 문자열이 없다")
                return
            }
            let lines = HwpDrawnTextLayout.lines(
                attributedString: combined, origin: CGPoint(x: 0, y: Fixtures.blockTop),
                lineWidth: Fixtures.wideWidth
            )
            let boxes = lines.map {
                HwpDrawnTextLayout.lineMetrics(of: $0.line, in: combined).boxHeight
            }
            expect(boxes) == [10, 10]
            expect(lines.map { Double($0.baselineOrigin.y) }).to(beCloseTo(
                Fixtures.expectedBaselines(boxes: [10, 10], advances: [34, 16]), within: 0.001
            ))
        }

        // MARK: 헬퍼

        private static func isStale(
            _ cache: [CoreHwp.HwpParaLineSegInternal], _ string: NSAttributedString
        ) -> Bool {
            HwpAbsoluteCachePlacer.cacheIsStale(run: cache, attributedString: string)
        }

        /// 줄 캐시 한 줄 — 줄 높이 `height`(HWPUNIT)만 의미가 있다.
        private static func lineCache(
            height: Int32
        ) throws -> [CoreHwp.HwpParaLineSegInternal] {
            try HwpSynthetic.lineSegParagraph("ab", segments: [(location: 0, height: height)])
                .paraLineSeg.paraLineSegInternalArray
        }
    }
#endif

@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 컨테이너 블록이 문단들을 `\n`으로 이은 문자열(`HwpPaginator.combinedAttributedString`)의
    /// 구분자가 앞 문단 마지막 글자의 조판 속성을 물려받는지 (#180).
    ///
    /// 속성 없는 `\n`은 CT 기본 글꼴(Helvetica 12pt)로 조판돼 그 줄의 상자
    /// (`HwpDrawnTextLayout.lineMetrics`)를 12pt로 부풀리고, 그 줄 뒤 문단 간격도 스타일 없는
    /// 글자에서 읽혀 0이 된다 — payload 없는 조각 블록은 이 문자열을 그대로 그린다
    /// (`HwpBlockContentWalker.plainText`).
    final class HwpCombinedBlockStringTests: XCTestCase {
        func testSeparatorInheritsTheLayoutAttributesOfThePrecedingParagraph() async throws {
            var host = try HwpSynthetic.textParagraph("글상자를 품은 문단")
            host.paraText?.charArray += [HwpChar(type: .extended, value: 11)]
            var textbox = try HwpSynthetic.inlineTextboxObject(
                width: 20000, height: 4000, text: "x"
            )
            textbox.shapeComponentArray[0].textBoxListArray[0].paragraphArray = [
                try HwpSynthetic.textParagraph("첫 문단"), try HwpSynthetic.textParagraph("둘째 문단"),
            ]
            host.ctrlHeaderArray = [.genShapeObject(textbox)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [host]
            )
            let paginator = HwpPaginator(
                sections: [section], index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let firstPage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(firstPage)
            let block = try XCTUnwrap(page.blocks.first { $0.kind == .textbox })
            let combined = try XCTUnwrap(block.attributedString)
            let separator = (combined.string as NSString).range(of: "\n")
            expect(separator.location).toNot(equal(NSNotFound))
            guard separator.location != NSNotFound else { return }
            let attributes = combined.attributes(at: separator.location, effectiveRange: nil)
            let preceding = combined.attributes(at: separator.location - 1, effectiveRange: nil)
            for key in [
                kCTFontAttributeName as NSAttributedString.Key,
                kCTParagraphStyleAttributeName as NSAttributedString.Key,
                HwpAttributedStringKey.baseFontSize,
                HwpAttributedStringKey.lineSpacing,
            ] {
                expect(attributes[key]).toNot(beNil(), description: key.rawValue)
                expect((attributes[key] as? NSObject)?.isEqual(preceding[key]))
                    .to(beTrue(), description: key.rawValue)
            }
            // 구분자 줄의 상자도 앞 문단 글자 크기(10pt)다 — 12pt로 부풀지 않는다.
            let lines = HwpDrawnTextLayout.lines(
                attributedString: combined, origin: .zero, lineWidth: 400
            )
            expect(lines.count).to(equal(2))
            expect(lines.first.map { HwpDrawnTextLayout.baselineAnchor(of: $0.line) })
                .to(beCloseTo(8.5, within: 0.001))
            guard lines.count == 2 else { return }
            expect(lines[1].baselineOrigin.y - lines[0].baselineOrigin.y)
                .to(beCloseTo(16, within: 0.001))
        }
    }
#endif

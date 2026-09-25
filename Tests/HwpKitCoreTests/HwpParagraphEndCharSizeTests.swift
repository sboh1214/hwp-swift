import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 문단 끝 글자(CR, 코드 13)의 글자 모양 크기가 문단 **마지막 줄**의 줄 상자와 비율 줄
    /// 간격 여분에 드는 계약 (#206) — 조판(`HwpTextRunBuilder.attachParagraphEndBaseFontSize`)이
    /// 그 크기를 문단 문자열 전체에 싣고(`hwp.paragraphEndBaseFontSize`), 세로 배치
    /// (`HwpDrawnTextLayout.LineMetrics`)가 `HwpDrawnLine.endsParagraph`인 줄에서만 되돌려 넣는다.
    ///
    /// 오라클은 한컴오피스 한글 12.30.0(macOS, 2026-09-21)이 함초롬바탕 본문 + 빈 꼬리 run으로
    /// CR 글자 모양을 준 합성 HWPX(`linesegarray` 없음)를 다시 저장한 줄 캐시와 내보낸 PDF다
    /// (`Tests/CoreHwpTests/Fixtures/paragraph-end-char-size/README.md`의 표와 이슈 본문): 10pt 본문 + 16pt
    /// CR 한 줄 문단 `vertsize` 1600·`baseline` 1360·160% `spacing` 960, 여러 줄 문단은 마지막
    /// 줄만 그렇고 앞 줄은 1000·850·600, 16pt 본문 + 10pt CR 1600, 10pt + 40pt CR 4000·3400·
    /// 2400, 고정 30 → 전진량 30·여백만 5 → 21·최소 12 → 16·최소 20 → 20, 상대 크기 50%의 CR도
    /// 1600, 표 마커 10pt + 30pt 표 + 16pt CR(`noori` 꼴) 3000·2550·170% 1120, 8pt 표 + 16pt CR
    /// 1600, 20pt 표 + 16pt CR 2000·1700·960, 한 줄 끝(10pt run) 앞 줄은 850·600 그대로이고
    /// 한 줄 끝이 16pt run이면 그 줄도 1600, 표 셀·글상자 안 문단도 같다. 우리 재조판은 그 픽스처
    /// 116줄 전부 한글 PDF 베이스라인과 0.10pt(한글 PDF의 0.12pt 장치 양자화) 안이다
    /// (`FixtureParagraphEndCharSizeTests`가 캐시 배치와 대조한다).
    final class HwpParagraphEndCharSizeTests: XCTestCase {
        private typealias Fixtures = LineBoxFixtures
        private static let endKey = HwpAttributedStringKey.paragraphEndBaseFontSize

        // MARK: 조판 — 키를 싣는 쪽

        /// 문단 끝 글자의 글자 모양이 마지막 글자와 다르면 그 **기본 크기**를 문단 문자열
        /// 전체에 싣는다 — CR 자체는 접혀 문자열에 없고(#137), 글자 run의 `baseFontSize`는
        /// 자기 글자 모양 그대로다.
        func testBuilderAttachesTheParagraphEndSizeToTheWholeString() {
            let built = Self.builder().build(
                paragraph: Self.paragraph(text: "가나\u{0D}", runs: [(0, 10), (2, 16)])
            )
            expect(built.string) == "가나"
            expect(Self.endSizes(in: built)) == [16, 16]
            expect(Self.baseSizes(in: built)) == [10, 10]
            // 상대 크기 50%의 CR도 기본 크기다 (한글 실측: `vertsize` 1600).
            let relative = Self.builder(relativeSizes: [16: 50]).build(
                paragraph: Self.paragraph(text: "가나\u{0D}", runs: [(0, 10), (2, 16)])
            )
            expect(Self.endSizes(in: relative)) == [16, 16]
        }

        /// 마지막 글자 모양 항목이 CR의 것이다 — 글자 모양이 하나뿐인 문단은 그 크기(본문과
        /// 같다), 상한으로 잘린 결과(`maxCharacters`)는 문단 끝이 아니라 키가 없다.
        func testTruncatedParagraphCarriesNoParagraphEndSize() {
            let paragraph = Self.paragraph(text: "가나다\u{0D}", runs: [(0, 10), (3, 16)])
            let whole = Self.builder().build(paragraph: paragraph)
            expect(Self.endSizes(in: whole)) == [16, 16, 16]
            let truncated = Self.builder().build(paragraph: paragraph, maxCharacters: 2)
            expect(truncated.string) == "가나"
            expect(Self.endSizes(in: truncated)) == [nil, nil]
            let uniform = Self.builder().build(
                paragraph: Self.paragraph(text: "가나\u{0D}", runs: [(0, 10)])
            )
            expect(Self.endSizes(in: uniform)) == [10, 10]
        }

        /// 빈 문단 앵커(#145)에도 싣는다 — 앵커는 첫 글자 모양으로 서지만 접힌 글자(하이픈
        /// 24)와 CR의 글자 모양이 다르면 CR 쪽이 그 줄의 상자다. 한 줄 끝 뒤 빈 줄 앵커
        /// (#137)는 CR 자리의 글자 모양을 이미 물려받고 키도 같은 값이다.
        func testEmptyParagraphAnchorsCarryTheParagraphEndSize() {
            let empty = Self.builder().build(
                paragraph: Self.paragraph(text: "\u{0D}", runs: [(0, 16)])
            )
            expect(HwpTextRunBuilder.isEmptyParagraphAnchor(empty)) == true
            expect(Self.endSizes(in: empty)) == [16]
            expect(Self.baseSizes(in: empty)) == [16]
            let hyphenOnly = Self.builder().build(
                paragraph: Self.paragraph(text: "\u{18}\u{0D}", runs: [(0, 10), (1, 16)])
            )
            expect(HwpTextRunBuilder.isEmptyParagraphAnchor(hyphenOnly)) == true
            expect(Self.baseSizes(in: hyphenOnly)) == [10]
            expect(Self.endSizes(in: hyphenOnly)) == [16]
            expect(Self.lineBoxes(of: hyphenOnly)) == [16]
            let trailingBreak = Self.builder().build(
                paragraph: Self.paragraph(text: "가\u{0A}\u{0D}", runs: [(0, 10), (2, 16)])
            )
            expect(trailingBreak.string) == "가\u{0A} "
            expect(Self.baseSizes(in: trailingBreak)) == [10, 10, 16]
            expect(Self.endSizes(in: trailingBreak)) == [16, 16, 16]
        }

        // MARK: 세로 배치 — 키를 읽는 쪽

        /// 여러 줄 문단은 **마지막 줄만** CR 크기를 받는다 — 10pt 세 줄 + 16pt CR, 160%:
        /// 상자 10·10·16, 전진량 16·16·25.6, 앵커 8.5·8.5·13.6 (한글 실측 A3). 측정 줄
        /// 프레임도 같다. CR이 본문보다 작으면(16pt 본문 + 10pt CR) 상자는 그대로 16이다.
        func testOnlyTheLastLineTakesTheParagraphEndSize() {
            let rule = Fixtures.rule(.percent, 160)
            let string = Self.withEndSize(16, Fixtures.threeLineParagraph(
                sizes: [(10, 10), (10, 10), (10, 10)], rule: rule
            ))
            expect(Fixtures.baselines(string)).to(beCloseTo(
                Fixtures.expectedBaselines(boxes: [10, 10, 16], advances: [16, 16, 25.6]),
                within: 0.001
            ))
            expect(Self.lineBoxes(of: string)) == [10, 10, 16]
            let frame = Self.measure(string, rule: rule)
            expect(frame.lines.map(\.boxHeight)) == [10, 10, 16]
            expect(frame.lines.map(\.baseline)).to(beCloseTo([8.5, 8.5, 13.6], within: 0.001))
            expect(frame.lines.map(\.origin.y)).to(beCloseTo([0, 16, 32], within: 0.001))
            expect(Double(frame.totalHeight)).to(beCloseTo(16 + 16 + 25.6, within: 0.001))

            let smaller = Self.withEndSize(10, Fixtures.threeLineParagraph(
                sizes: [(16, 16), (16, 16), (16, 16)], rule: rule
            ))
            expect(Self.lineBoxes(of: smaller)) == [16, 16, 16]
            expect(Fixtures.baselines(smaller)).to(beCloseTo(
                Fixtures.expectedBaselines(boxes: [16, 16, 16], advances: [25.6, 25.6, 25.6]),
                within: 0.001
            ))
        }

        /// 줄 간격 종류마다 CR 크기가 든 상자(16)에 규칙을 적용한다 — 비율 100 → 16, 160 →
        /// 25.6, 고정 30 → 30, 여백만 5 → 21, 최소 12 → 16, 최소 20 → 20 (한글 실측 B1~B9).
        /// 10pt + 40pt CR은 상자 40·전진량 64 (A9).
        func testEveryLineSpacingKindAppliesToTheBoxWithTheParagraphEndSize() {
            let table: [Fixtures.RuleCase<CGFloat>] = [
                .init(.percent, 100, 16), .init(.percent, 160, 25.6), .init(.fixed, 30, 30),
                .init(.marginOnly, 5, 21), .init(.atLeast, 12, 16), .init(.atLeast, 20, 20),
            ]
            for row in table {
                let string = Self.withEndSize(16, Self.singleLine(size: 10, rule: row.rule))
                let frame = Self.measure(string, rule: row.rule)
                expect(frame.lines.map(\.boxHeight)).to(equal([16]), description: row.label)
                expect(Double(frame.totalHeight))
                    .to(beCloseTo(Double(row.expected), within: 0.001), description: row.label)
                expect(Fixtures.baselines(string))
                    .to(beCloseTo([Double(Fixtures.blockTop + 13.6)], within: 0.001), description: row.label)
            }
            let large = Self.withEndSize(
                40, Self.singleLine(size: 10, rule: Fixtures.rule(.percent, 160))
            )
            expect(Self.lineBoxes(of: large)) == [40]
            expect(Double(Self.measure(large, rule: Fixtures.rule(.percent, 160)).totalHeight))
                .to(beCloseTo(64, within: 0.001))
        }

        /// 개체 줄 — CR 크기는 상자와 비율 여분 기준 둘 다에 든다 (한글 실측 F1·F3·F5):
        /// 8pt 표 + 10pt 글 + 16pt CR은 상자 16(CR이 정한다)·160% 전진량 25.6, 20pt 표는 상자
        /// 20·전진량 20 + 9.6(여분 기준은 CR 16), 마커 10pt만 있는 30pt 표 + 16pt CR(`noori`
        /// 2번째 문단 꼴)은 170%에서 30 + 11.2.
        func testObjectLinesTakeTheParagraphEndSizeForBoxAndShare() {
            let rule = Fixtures.rule(.percent, 160)
            let small = Self.withEndSize(16, Self.objectLine(objectHeight: 8, rule: rule))
            expect(Self.lineBoxes(of: small)) == [16]
            expect(Double(Self.measure(small, rule: rule).totalHeight))
                .to(beCloseTo(25.6, within: 0.001))
            expect(Fixtures.baselines(small))
                .to(beCloseTo([Double(Fixtures.blockTop + 13.6)], within: 0.001))

            let tall = Self.withEndSize(16, Self.objectLine(objectHeight: 20, rule: rule))
            expect(Self.lineBoxes(of: tall)) == [20]
            expect(Double(Self.measure(tall, rule: rule).totalHeight))
                .to(beCloseTo(20 + 9.6, within: 0.001))
            expect(Fixtures.baselines(tall))
                .to(beCloseTo([Double(Fixtures.blockTop + 17)], within: 0.001))

            let noori = Fixtures.rule(.percent, 170)
            let markerOnly = Self.withEndSize(16, Fixtures.applying(
                noori, to: Fixtures.objectMarker(height: 30, attributes: Fixtures.attributes(size: 10))
            ))
            expect(Self.lineBoxes(of: markerOnly)) == [30]
            expect(Double(Self.measure(markerOnly, rule: noori).totalHeight))
                .to(beCloseTo(30 + 11.2, within: 0.001))
            // CR 크기가 없으면 여분은 마커의 10pt 기준 7이다 — 이슈 #206의 표.
            let bare = Fixtures.applying(
                noori, to: Fixtures.objectMarker(height: 30, attributes: Fixtures.attributes(size: 10))
            )
            expect(Double(Self.measure(bare, rule: noori).totalHeight))
                .to(beCloseTo(37, within: 0.001))
        }

        /// 한 줄 끝(코드 10)으로 나뉜 앞 줄은 CR 크기를 받지 않는다 — 10pt 글 + 10pt run의 한
        /// 줄 끝 + 빈 줄 앵커(CR 자리, 16pt) 문단은 첫 줄 상자 10·전진량 16, 빈 줄 16·25.6
        /// (한글 실측 D1). 한 줄 끝이 16pt run이면 그 글자 자신의 크기로 첫 줄도 16 (D3).
        func testLineBreakLinesKeepTheirOwnSizeAndTheEmptyLineTakesTheParagraphEnd() {
            let rule = Fixtures.rule(.percent, 160)
            let small = Fixtures.attributes(size: 10)
            let large = Fixtures.attributes(size: 16)
            let output = NSMutableAttributedString(string: "ab", attributes: small)
            output.append(Fixtures.lineBreak(attributes: small))
            output.append(Fixtures.emptyLineAnchor(attributes: large))
            let string = Self.withEndSize(16, Fixtures.applying(rule, to: output))
            expect(Self.lineBoxes(of: string)) == [10, 16]
            expect(Fixtures.baselines(string)).to(beCloseTo(
                Fixtures.expectedBaselines(boxes: [10, 16], advances: [16, 25.6]), within: 0.001
            ))
            let frame = Self.measure(string, rule: rule)
            expect(frame.lines.map(\.boxHeight)) == [10, 16]
            expect(Double(frame.totalHeight)).to(beCloseTo(16 + 25.6, within: 0.001))

            let breakInLarge = NSMutableAttributedString(string: "ab", attributes: small)
            breakInLarge.append(Fixtures.lineBreak(attributes: large))
            breakInLarge.append(Fixtures.emptyLineAnchor(attributes: large))
            let largeBreak = Self.withEndSize(16, Fixtures.applying(rule, to: breakInLarge))
            expect(Self.lineBoxes(of: largeBreak)) == [16, 16]
            expect(Fixtures.baselines(largeBreak)).to(beCloseTo(
                Fixtures.expectedBaselines(boxes: [16, 16], advances: [25.6, 25.6]), within: 0.001
            ))
        }

        /// 다음 단·쪽으로 이어지는 조각(`hwp.continuedParagraphFragment`)의 끝 줄은 문단
        /// 끝이 아니라 CR 크기가 들지 않는다 — 진짜 마지막 조각만 받는다.
        func testContinuedFragmentDoesNotTakeTheParagraphEndSize() {
            let rule = Fixtures.rule(.percent, 160)
            let string = Self.withEndSize(16, Fixtures.threeLineParagraph(
                sizes: [(10, 10), (10, 10), (10, 10)], rule: rule
            ))
            let continued = NSMutableAttributedString(attributedString: string)
            continued.addAttribute(
                HwpAttributedStringKey.continuedParagraphFragment, value: NSNumber(value: true),
                range: NSRange(location: 0, length: continued.length)
            )
            expect(Self.lineBoxes(of: continued)) == [10, 10, 10]
            expect(Fixtures.baselines(continued)).to(beCloseTo(
                Fixtures.expectedBaselines(boxes: [10, 10, 10], advances: [16, 16, 16]),
                within: 0.001
            ))
            expect(Double(Self.measure(continued, rule: rule).totalHeight))
                .to(beCloseTo(48, within: 0.001))
        }

        /// 문단들을 LF로 이은 결합 문자열(컨테이너 블록)은 문단마다 자기 CR 크기를 받는다 —
        /// 앞 문단(16)의 끝 줄과 뒤 문단(40)의 끝 줄이 각각이고, 앞 문단의 키는 뒤 문단에
        /// 새지 않는다 (표 셀·글상자 안 문단의 한글 실측 G1·G2와 같은 규칙).
        func testCombinedStringAppliesEachParagraphsOwnEndSize() {
            let rule = Fixtures.rule(.percent, 160)
            let small = Fixtures.attributes(size: 10)
            let first = Self.withEndSize(16, NSAttributedString(string: "ab\n", attributes: small))
            let second = Self.withEndSize(40, NSAttributedString(string: "cd", attributes: small))
            let combined = NSMutableAttributedString(attributedString: first)
            combined.append(second)
            let string = Fixtures.applying(rule, to: combined)
            expect(Self.lineBoxes(of: string)) == [16, 40]
            expect(Fixtures.baselines(string)).to(beCloseTo(
                Fixtures.expectedBaselines(boxes: [16, 40], advances: [25.6, 64]), within: 0.001
            ))
            // 뒤 문단이 CR 크기를 싣지 않으면 그 줄은 본문 10 그대로다.
            let plainSecond = NSMutableAttributedString(attributedString: first)
            plainSecond.append(NSAttributedString(string: "cd", attributes: small))
            expect(Self.lineBoxes(of: Fixtures.applying(rule, to: plainSecond))) == [16, 10]
        }

        /// 밴드 바닥 구분선이 빼는 마지막 줄 줄 간격(`measuredTrailingSpacing`)도 CR 크기가 든
        /// 줄 상자 기준이다 — 10pt 글 + 16pt CR 줄은 고정 30에서 30 − 16 = 14, 이어지는 조각의 끝
        /// 줄은 CR이 들지 않아 30 − 10 = 20, CR이 글보다 작으면(8pt) 글 상자 기준 20.
        func testTrailingSpacingIncludesTheParagraphEndSize() {
            let fixed = Fixtures.rule(.fixed, 30)
            let string = Self.withEndSize(16, Self.singleLine(size: 10, rule: fixed))
            let spacing = { (string: NSAttributedString) in
                Double(HwpColumnBandController.measuredTrailingSpacing(
                    of: string, lineWidth: Fixtures.wideWidth
                ))
            }
            expect(spacing(string)).to(beCloseTo(14, within: 0.001))
            let continued = NSMutableAttributedString(attributedString: string)
            continued.addAttribute(
                HwpAttributedStringKey.continuedParagraphFragment, value: NSNumber(value: true),
                range: NSRange(location: 0, length: continued.length)
            )
            expect(spacing(continued)).to(beCloseTo(20, within: 0.001))
            expect(spacing(Self.withEndSize(8, Self.singleLine(size: 10, rule: fixed))))
                .to(beCloseTo(20, within: 0.001))
        }

        /// 밑줄 기준의 줄 상자에도 **마지막 줄에만** 문단 끝 글자가 든다 (#226) — 10pt 글 + 12pt
        /// 개체 줄의 상자는 마지막 줄이면 16pt CR이 정하고, 앞 조각의 끝 줄(문단 끝 아님)이면
        /// 개체 12가 정한다. 두께 기준은 어느 쪽이든 글자 10pt다 — 한글 12.30 실측: 10pt 밑줄 +
        /// 40pt 문단 끝 글자 줄의 밑줄은 40pt 상자 바닥 −6.24pt에 두께 0.36pt(10pt 몫).
        func testUnderlineReferenceSeesTheParagraphEndBox() {
            let string = Self.withEndSize(16, Self.objectLine(objectHeight: 12, rule: nil))
            let line = CTLineCreateWithAttributedString(string)
            let last = HwpDrawnTextLayout.underlineReference(of: line, endsParagraph: true)
            expect(last.lineBoxHeight).to(beCloseTo(16, within: 0.001))
            expect(last.textFontSize).to(beCloseTo(10, within: 0.001))
            let continued = HwpDrawnTextLayout.underlineReference(of: line, endsParagraph: false)
            expect(continued.lineBoxHeight).to(beCloseTo(12, within: 0.001))
            expect(continued.textFontSize).to(beCloseTo(10, within: 0.001))
        }

        // MARK: 실물 — `noori` 2번째 문단

        /// 이슈 #206의 문단 — 68.69pt 글자처럼 취급 표의 마커(글자 모양 10pt)와 16pt 문단 끝
        /// 글자, 비율 170%. 줄 캐시 없이 조판하면 줄 상자 68.69·추가 간격 11.20(= 16 × 0.7)·
        /// 전진량 79.89pt여야 한다 (한글이 저장한 줄 캐시 `vertsize` 6869·`spacing` 1120;
        /// 종전에는 마커의 10pt 기준 7.00·75.69). HWP·HWPX 둘 다.
        func testNooriSecondParagraphReflowsToTheSavedLineCache() throws {
            for file in try [Self.fixture("noori"), Self.hwpxFixture("noori")] {
                let index = HwpIndex(from: file)
                let section = try XCTUnwrap(file.displaySectionArray.first)
                let paragraph = section.paragraph[1]
                let charShapes = paragraph.paraCharShape.shapeId.compactMap { index.charShape(id: $0) }
                expect(charShapes.map(\.baseSize)) == [1000, 1600]
                let built = HwpTextRunBuilder(
                    index: index, fontResolver: .testDeterministic,
                    sizeResolver: HwpObjectSizeResolver(
                        paperSize: CGSize(width: 595.28, height: 841.89),
                        contentSize: CGSize(width: 482.3, height: 700),
                        columnWidth: 482.3
                    )
                ).build(paragraph: paragraph)
                expect(Self.endSizes(in: built).compactMap { $0 }.allSatisfy { $0 == 16 }) == true
                let paraShape = index.paraShapeOrDefault(for: paragraph)
                expect(HwpLineSpacingRule(paraShape: paraShape)) == Fixtures.rule(.percent, 170)
                let frame = HwpParagraphLayout().layout(
                    attributedString: built, paraShape: paraShape, columnWidth: 482.3
                )
                expect(frame.lines.count) == 1
                let line = try XCTUnwrap(frame.lines.first)
                expect(Double(line.boxHeight)).to(beCloseTo(68.69, within: 0.001))
                expect(Double(frame.totalHeight - line.boxHeight)).to(beCloseTo(11.2, within: 0.001))
                expect(Double(frame.totalHeight)).to(beCloseTo(79.89, within: 0.001))
                // 렌더도 같은 전진량이다 — 마커만 있는 한 줄의 baseline은 상자 상단 + 0.85 × 68.69.
                let drawn = HwpDrawnTextLayout.lines(
                    attributedString: built, origin: .zero, lineWidth: 482.3
                )
                expect(drawn.map { Double($0.baselineOrigin.y) })
                    .to(beCloseTo([68.69 * HwpRenderTuning.Text.baselineAnchorRatio], within: 0.001))
            }
        }

        // MARK: 헬퍼

        private static func fixture(_ id: String) throws -> CoreHwp.HwpFile {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/Fixtures/\(id)/document.hwp")
            return try CoreHwp.HwpFile(fromPath: url.path)
        }

        private static func hwpxFixture(_ id: String) throws -> CoreHwp.HwpFile {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CoreHwpTests/HwpxFixtures/\(id)/document.hwpx")
            return try CoreHwp.HwpFile(fromPath: url.path)
        }

        /// 글자 모양 id = 기본 크기(pt)인 사전의 빌더 — `relativeSizes`는 id별 상대 크기(%).
        private static func builder(relativeSizes: [UInt32: UInt8] = [:]) -> HwpTextRunBuilder {
            var shapes: [UInt32: CoreHwp.HwpCharShape] = [:]
            for size: UInt32 in [8, 10, 16, 40] {
                shapes[size] = CoreHwp.HwpCharShape(
                    hwpxFaceId: [0, 0, 0, 0, 0, 0, 0],
                    faceScaleX: Array(repeating: 100, count: 7),
                    faceSpacing: Array(repeating: 0, count: 7),
                    faceRelativeSize: Array(repeating: relativeSizes[size] ?? 100, count: 7),
                    faceLocation: Array(repeating: 0, count: 7),
                    baseSize: Int32(size) * 100,
                    property: CoreHwp.HwpCharShapeProperty(),
                    shadowIntervalX: 0, shadowIntervalY: 0,
                    faceColor: CoreHwp.HwpColor(), underlineColor: CoreHwp.HwpColor(),
                    shadeColor: CoreHwp.HwpColor(255, 255, 255),
                    shadowColor: CoreHwp.HwpColor(192, 192, 192),
                    borderFillId: nil, strikethroughColor: nil
                )
            }
            return HwpTextRunBuilder(
                index: HwpIndex(
                    charShapes: shapes, paraShapes: [:], borderFills: [:], tabDefs: [:], styles: [:],
                    bullets: [:], numberings: [:], binData: [:], faceNamesKorean: [:],
                    faceNamesEnglish: [:], faceNamesChinese: [:], faceNamesJapanese: [:],
                    faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
                ),
                fontResolver: .testDeterministic
            )
        }

        /// WCHAR 스트림 `text`와 (시작 위치, 글자 모양 id) 목록의 문단.
        private static func paragraph(text: String, runs: [(UInt32, UInt32)]) -> CoreHwp.HwpParagraph {
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = text.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
            paragraph.paraText = paraText
            var paraCharShape = CoreHwp.HwpParaCharShape()
            paraCharShape.startingIndex = runs.map(\.0)
            paraCharShape.shapeId = runs.map(\.1)
            paragraph.paraCharShape = paraCharShape
            return paragraph
        }

        /// 글자마다 `hwp.paragraphEndBaseFontSize` (없으면 nil).
        private static func endSizes(in string: NSAttributedString) -> [Double?] {
            (0 ..< string.length).map {
                (string.attribute(endKey, at: $0, effectiveRange: nil) as? NSNumber)?.doubleValue
            }
        }

        /// 글자마다 `hwp.baseFontSize` (없으면 nil).
        private static func baseSizes(in string: NSAttributedString) -> [Double?] {
            (0 ..< string.length).map {
                (string.attribute(
                    HwpAttributedStringKey.baseFontSize, at: $0, effectiveRange: nil
                ) as? NSNumber)?.doubleValue
            }
        }

        /// 문자열 전체에 CR 기본 크기를 싣는다 (`attachParagraphEndBaseFontSize`와 같은 꼴).
        private static func withEndSize(_ size: CGFloat, _ string: NSAttributedString) -> NSAttributedString {
            let output = NSMutableAttributedString(attributedString: string)
            output.addAttribute(
                endKey, value: NSNumber(value: Double(size)),
                range: NSRange(location: 0, length: output.length)
            )
            return output
        }

        private static func singleLine(size: CGFloat, rule: HwpLineSpacingRule?) -> NSAttributedString {
            Fixtures.applying(
                rule, to: NSAttributedString(string: "ab", attributes: Fixtures.attributes(size: size))
            )
        }

        /// `ab▯` — 10pt 글자 + `objectHeight`pt 글자처럼 취급 개체 한 줄.
        private static func objectLine(objectHeight: CGFloat, rule: HwpLineSpacingRule?) -> NSAttributedString {
            let text = Fixtures.attributes(size: 10)
            let output = NSMutableAttributedString(string: "ab", attributes: text)
            output.append(Fixtures.objectMarker(height: objectHeight, attributes: text))
            return Fixtures.applying(rule, to: output)
        }

        /// 렌더 줄마다 줄 상자 높이 (`LineMetrics.boxHeight`).
        private static func lineBoxes(of string: NSAttributedString) -> [CGFloat] {
            HwpDrawnTextLayout.lines(
                attributedString: string, origin: CGPoint(x: 0, y: Fixtures.blockTop),
                lineWidth: Fixtures.wideWidth
            ).map { HwpDrawnTextLayout.lineMetrics(of: $0.line, in: string).boxHeight }
        }

        /// 측정 — `rule`의 문단 모양(문단 간격 0)을 `attachParagraphStyle`로 달아 잰다.
        private static func measure(_ string: NSAttributedString, rule: HwpLineSpacingRule) -> HwpParagraphFrame {
            let shape = Fixtures.paraShape(rule: rule)
            let styled = NSMutableAttributedString(attributedString: string)
            HwpParagraphLayout.attachParagraphStyle(to: styled, paraShape: shape)
            return HwpParagraphLayout().layout(
                attributedString: styled, paraShape: shape, columnWidth: Fixtures.wideWidth
            )
        }
    }
#endif

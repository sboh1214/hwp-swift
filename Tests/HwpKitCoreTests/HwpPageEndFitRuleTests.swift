import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽 끝 적합 판정의 규칙 단위 가드와 각주가 있는 쪽 (#222) — 배치 사례는
    /// `HwpPageEndLineBoxFitTests`.
    final class HwpPageEndFitRuleTests: XCTestCase {
        private static func line(y: CGFloat, box: CGFloat) -> HwpLineFrame {
            HwpLineFrame(
                origin: CGPoint(x: 0, y: y), width: 100, baseline: box * 0.85,
                attributedRange: NSRange(location: Int(y), length: 1), boxHeight: box
            )
        }

        /// 글자 모양 0은 10pt, 1은 20pt인 인덱스 (문단 모양 0은 160%).
        private static func twoSizeIndex() throws -> HwpIndex {
            HwpIndex(
                charShapes: [
                    0: try HwpNumberingHeadingRenderTests.charShape(baseSize: 1000),
                    1: try HwpNumberingHeadingRenderTests.charShape(baseSize: 2000),
                ],
                paraShapes: [0: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, tabDefId: 0, lineSpacing2: 160
                )],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
        }

        /// 판정은 엄격 부등호다 — 상자 하단이 경계에 닿으면 안 들어가고, 한 HWPUNIT(0.01pt)
        /// 안쪽이면 들어간다. 부동소수 누적 오차(1e-12)는 경계를 뒤집지 않는다.
        func testPageEndFitIsStrictAtTheBoundary() {
            expect(HwpPageEndFit.fits(640 + 17.62, in: 657.62)) == false
            expect(HwpPageEndFit.fits(640 + 17.61, in: 657.62)) == true
            expect(HwpPageEndFit.fits(657.62 + 1e-12, in: 657.62)) == false
            expect(HwpPageEndFit.fits(657.62 - 1e-12, in: 657.62)) == false
            expect(HwpPageEndFit.fits(0, in: -1)) == false
        }

        /// 줄의 적합 높이는 상자다 — 전진량보다 작든(비율 여분) 크든(고정 줄 간격이 상자보다
        /// 작음) 상자로 잰다. 조각 전체의 적합 높이는 줄마다 (상단 + 상자)의 최댓값이라, 겹친 줄
        /// (앞 줄 상자가 뒤 줄 상자보다 아래로 내려감)에서 마지막 줄만 보지 않는다.
        func testFitHeightIsTheLineBoxAndTheLowestBoxBoundsAFragment() {
            let spaced = HwpFragmentLineAdvances(
                lines: [Self.line(y: 0, box: 16), Self.line(y: 25.6, box: 16)], textHeight: 51.2
            )
            expect(spaced.advance(0)).to(beCloseTo(25.6, within: 0.001))
            expect(spaced.fitHeight(0)).to(beCloseTo(16, within: 0.001))
            expect(spaced.fitHeight(from: 0, through: 1)).to(beCloseTo(41.6, within: 0.001))
            // 고정 16pt에 30pt 줄 다음 10pt 줄: 첫 줄 상자 바닥 30이 둘째 줄 상자 바닥 26보다 낮다.
            let overlapped = HwpFragmentLineAdvances(
                lines: [Self.line(y: 0, box: 30), Self.line(y: 16, box: 10)], textHeight: 32
            )
            expect(overlapped.fitHeight(0)).to(beCloseTo(30, within: 0.001))
            expect(overlapped.fitHeight(from: 0, through: 1)).to(beCloseTo(30, within: 0.001))
            // 상자 정보가 없는 줄(합성 줄 프레임)과 원점이 비단조인 문단은 전진량으로 잰다.
            let unknownBox = HwpFragmentLineAdvances(
                lines: [Self.line(y: 0, box: 0), Self.line(y: 16, box: 0)], textHeight: 32
            )
            expect(unknownBox.fitHeight(0)).to(beCloseTo(16, within: 0.001))
            let degraded = HwpFragmentLineAdvances(
                lines: [Self.line(y: 16, box: 10), Self.line(y: 0, box: 10)], textHeight: 40
            )
            expect(degraded.fitHeight(0)).to(beCloseTo(20, within: 0.001))
        }

        /// 텍스트 몫이 줄 캐시 높이인 문단의 마지막 줄은 캐시의 줄 상자 바닥까지다 — 높이와 같은
        /// 출처. 마지막 줄 전진량은 캐시 잔여(여기서는 48 − 32 = 16)이고 그 가운데 캐시 줄 간격 몫
        /// 6을 뺀 10이 적합 높이다. CT 줄이 캐시보다 아래로 밀려 캐시 바닥이 마지막 줄 상단 위면
        /// 그 줄은 판정을 늘리지 않는다 — 앞 줄 상자가 정한다. 다시 잰 나머지는 캐시 바닥을 버린다.
        func testCachedHeightRemainderJudgesTheLastLineByTheCachedBox() {
            let lines = [0, 16, 32].map { Self.line(y: $0, box: 10) }
            let cached = HwpFragmentRemainder(
                lines: lines, textHeight: 48, measuredWidth: 100, heightIsMeasured: false,
                fitSource: HwpFragmentFitSource(cachedLastLineBoxBottom: 42)
            )
            expect(cached.remainingFitHeight).to(beCloseTo(42, within: 0.001))
            expect(cached.fit(in: 42).count) == 2
            expect(cached.fit(in: 42.01).count) == 3
            let shifted = HwpFragmentRemainder(
                lines: lines, textHeight: 48, measuredWidth: 100, heightIsMeasured: false,
                fitSource: HwpFragmentFitSource(cachedLastLineBoxBottom: 20)
            )
            expect(shifted.remainingFitHeight).to(beCloseTo(26, within: 0.001))
            // 캐시 바닥이 CT 상자와 다른 나머지(`shifted`)를 다시 재야 버리는지가 드러난다 — 캐시
            // 바닥을 물려받으면 26·3줄이다.
            var remeasured = shifted
            remeasured.replace(
                with: HwpParagraphFrame(totalHeight: 48, lines: lines),
                textHeight: 48, width: 150, range: NSRange(location: 0, length: 3)
            )
            expect(remeasured.remainingFitHeight).to(beCloseTo(42, within: 0.001))
            expect(remeasured.fit(in: 42).count) == 2
            // 줄이 없는 문단(빈 문단 앵커)은 따로 잰 상자, 그것도 없으면 텍스트 몫 전체다.
            let empty = HwpFragmentRemainder(
                lines: [], textHeight: 16, measuredWidth: 100, heightIsMeasured: true,
                fitSource: HwpFragmentFitSource(emptyLineBoxHeight: 10)
            )
            expect(empty.remainingFitHeight).to(beCloseTo(10, within: 0.001))
            let bare = HwpFragmentRemainder(
                lines: [], textHeight: 16, measuredWidth: 100, heightIsMeasured: true
            )
            expect(bare.remainingFitHeight).to(beCloseTo(16, within: 0.001))
        }

        /// 한글 FN(`probes/222`): 각주가 있는 쪽의 본문 하단은 각주 영역 상단(구분선 위 여백
        /// 8.5 + 구분선 아래 5.67 + 각주 줄 **상자** 10 = 24.17)이고, 20pt 줄(상자 20, 전진량 32)은
        /// 그 위 남은 25pt에 남는다. 줄 캐시 없는 각주도 마지막 줄의 줄 간격 여분(6)은 스택에
        /// 들지 않는다 — 들면 영역이 30.17로 커져 상자 20이 남은 19에 안 들어간다.
        func testLineAboveAFootnoteAreaStaysWhenItsBoxFits() async throws {
            var filler = try HwpSynthetic.splitParagraphWithNoteMarkers(
                lines: (0 ..< 8).map { (characters: 5, marker: $0 == 0) }, segments: []
            )
            filler.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [HwpSynthetic.noteParagraph(
                    " 각주 본문",
                    autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                )]
            ))]
            var target = try HwpSynthetic.textParagraph("FN 20pt")
            var charShape = CoreHwp.HwpParaCharShape()
            charShape.startingIndex = [0]
            charShape.shapeId = [1]
            target.paraCharShape = charShape
            let index = try Self.twoSizeIndex()
            // 본문 = 구역 첫 문단 16 + 채움 여덟 줄 128 + 각주 영역 24.17 + 남은 25.
            let contentHeight: CGFloat = 16 + 128 + 24.17 + 25
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(MeasuredLineFragmentSupport.sectionDef(
                    columnWidth: 300, contentHeight: contentHeight
                ))],
                bodyParagraphs: [filler, target, try HwpSynthetic.textParagraph("뒤 문단")]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            let first = try XCTUnwrap(pages.first)
            let body = try XCTUnwrap(first.blocks.first {
                $0.attributedString?.string.hasPrefix("FN 20pt") == true
            })
            let note = try XCTUnwrap(first.blocks.first { $0.kind == .footnote })
            expect(body.frame.minY).to(beCloseTo(144, within: 0.001))
            expect(note.frame.height).to(beCloseTo(10, within: 0.001))
            expect(note.frame.maxY).to(beCloseTo(contentHeight, within: 0.001))
            guard case let .footnote(payload) = note.payload else {
                fail("각주 블록의 payload가 각주가 아니다")
                return
            }
            // 줄 상자 바닥(144 + 20)은 구분선 위 여백까지 든 영역 상단(본문 − 24.17) 위다.
            expect(body.frame.minY + 20).to(beLessThan(contentHeight - 24.17))
            expect(payload.separatorLine.minY).to(beGreaterThan(body.frame.minY + 20))
        }
    }
#endif

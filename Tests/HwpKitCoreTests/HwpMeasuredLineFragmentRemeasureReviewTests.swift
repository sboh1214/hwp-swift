import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 재측정(`HwpMeasuredLineFragmentRemeasureTests`)의 리뷰 워크플로가 잡은 축들: 넓은 단에서
    /// 다시 재도 두 줄인 조각의 표식, 한 줄 문단의 통째 이동, 옮기지 않은 조각 블록의 표식 보존,
    /// 조각 부분 문자열이 아닌 문단 전체의 줄 높이 지표, 가운데 조각의 문단 아래 간격, 첫 줄
    /// ascent 초과분의 기준.
    final class HwpMeasuredLineFragmentRemeasureReviewTests: XCTestCase {
        private typealias Support = MeasuredLineFragmentSupport
        private typealias Columns = MeasuredLineRemeasureSupport

        /// 좁은 단(30자) → 넓은 단(61자): 123자 문단은 좁은 단에서 두 줄이 들어가고 나머지
        /// 63자는 넓은 단에서 61자 + 2자 두 줄이다 — 자연 폭이 1.06배 안이라 표식이 없으면 접혀
        /// 두 줄 상자에 한 줄만 그려지므로, 다시 잰 조각도 표식을 단다.
        func testWiderColumnRemeasuredTwoLineFragmentStaysMarked() async throws {
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 123))
            let (paginator, _) = try Columns.columns(
                charactersPerLine: [30, 61], contentHeight: 56, bodyParagraphs: [paragraph]
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let fragments = Columns.fragments(on: page)
            expect(fragments.map { $0.attributedString?.length }) == [60, 63]
            guard fragments.count == 2, let tail = fragments[1].attributedString else { return }
            expect(fragments[1].frame.height).to(beCloseTo(32, within: 0.5))
            expect(Columns.drawnLineLengths(of: fragments[1])) == [61, 2]
            expect(Support.isMarked(tail)).to(beTrue())
            expect(HwpDrawnTextLayout.lines(
                attributedString: HwpParagraphLayout.strippingMeasuredLineMarker(tail),
                origin: .zero, lineWidth: fragments[1].frame.width
            ).count) == 1
        }

        /// 한 줄로 잰 문단이 부분 채운 단에 안 들어가 통째로 좁은 단(30자)으로 옮겨지면 그 폭으로
        /// 다시 재어 세 줄(48pt)이 되는데, 목적 단(40pt)보다 크므로 조각 루프가 나눈다 — 좁은
        /// 단에 두 줄(60자, 32pt), 마지막 글자는 다음 쪽 (PR 리뷰: 통째로 놓으면 여백·뒤 내용으로
        /// 넘친다). 종전에는 한 줄 상자(16pt)에 세 줄이 그려졌다.
        func testSingleLineParagraphMovedWholeToANarrowerColumnIsRemeasuredAndSplit() async throws {
            let first = try HwpSynthetic.textParagraph(String(repeating: "가", count: 61))
            let second = try HwpSynthetic.textParagraph(String(repeating: "나", count: 61))
            let (paginator, widths) = try Columns.columns(
                charactersPerLine: [61, 30], contentHeight: 40, bodyParagraphs: [first, second]
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }
            let moved = try XCTUnwrap(pages[0].blocks.first {
                $0.attributedString?.string.contains("나") == true
            })
            expect(moved.attributedString?.length) == 60
            expect(moved.frame.width).to(beCloseTo(widths[1], within: 0.01))
            // 마지막 줄의 ascent 초과분 2pt(#164)는 다음 조각 몫이라 30 + 18 = 48pt다.
            expect(moved.frame.height).to(beGreaterThanOrEqualTo(29.5))
            expect(moved.frame.height).to(beLessThanOrEqualTo(32.5))
            expect(Columns.drawnLineLengths(of: moved)) == [30, 30]
            expect(Support.isMarked(try XCTUnwrap(moved.attributedString))).to(beTrue())
            let rest = try XCTUnwrap(pages[1].blocks.first {
                $0.attributedString?.string.contains("나") == true
            })
            expect(rest.attributedString?.length) == 1
            expect(moved.frame.height + rest.frame.height).to(beCloseTo(48, within: 0.5))
            expect(Columns.drawnLineLengths(of: rest)) == [1]
        }

        /// 통째로 옮겨 다시 잰 한 줄 문단은 **다시 잰 문자열**을 그린다 (PR 리뷰): 단 너비 50%
        /// 글자처럼 취급 개체의 예약은 목적 단으로 다시 풀리므로, 원본 문자열(넓은 단의 예약)을
        /// 그리면 예약 폭이 그려지는 개체 폭과 갈리고 좁은 단에서 줄이 늘어 한 줄 상자를 넘친다.
        func testWholeMovedParagraphRendersTheRemeasuredReservation() async throws {
            let first = try HwpSynthetic.textParagraph(String(repeating: "가", count: 61))
            var second = HwpSynthetic.paragraphWithInlineControl(
                prefix: String(repeating: "나", count: 5), suffix: ""
            )
            second.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.columnRelativeInlineObject(
                widthPercent: 5000, heightPercent: 200, instanceId: 4
            ))]
            let (paginator, widths) = try Columns.columns(
                charactersPerLine: [61, 30], contentHeight: 40, bodyParagraphs: [first, second]
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            guard let page = pages.first else { return }
            let moved = try XCTUnwrap(page.blocks.first {
                $0.attributedString?.string.contains("나") == true
            })
            expect(moved.frame.width).to(beCloseTo(widths[1], within: 0.01))
            let object = try XCTUnwrap(
                InlineControlFragmentSupport.objectBlocks(on: page, instanceId: 4).first
            )
            let reserved = try XCTUnwrap(InlineControlFragmentSupport.reservedMarkerWidth(
                in: try XCTUnwrap(moved.attributedString), controlIndex: 0
            ))
            // 예약 = 그려지는 폭 = 좁은 단의 50% (넓은 단의 50%가 아니다).
            expect(object.frame.width).to(beCloseTo(widths[1] / 2, within: 0.05))
            expect(reserved).to(beCloseTo(object.frame.width, within: 0.05))
            expect(Columns.drawnLineLengths(of: moved)) == [6]
            expect(object.frame.maxX).to(beLessThanOrEqualTo(moved.frame.maxX + 0.01))
        }

        /// 쪽·단 경계로 나뉜 문단의 뒤 조각 블록(줄 목록 없는 단위 하나)이 밴드 닫힘 재배치를
        /// 지나도 제자리(같은 폭)에 남으면 문자열·높이 그대로다 — 단위가 하나라 줄 수를 모르는
        /// 표식 판정을 다시 하면 표식이 벗겨져 두 줄 상자에 한 줄만 그려졌다(#166 증상, HEAD의
        /// 잔여 결함). 등폭 2단 본문 48pt: 첫 쪽 첫 단은 구역 첫 문단과 채움 둘, 둘째 단은 121자
        /// 문단의 세 줄, 둘째 쪽 첫 단에 뒤 조각(31자, 두 줄)과 뒤 문단이 놓인 채 문서가 끝난다.
        func testUnmovedTailFragmentKeepsItsMarkerThroughRebalance() async throws {
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 121))
            let (paginator, _) = try Columns.columns(
                charactersPerLine: [30, 30], contentHeight: 48,
                bodyParagraphs: [
                    try HwpSynthetic.textParagraph("채움 하나"),
                    try HwpSynthetic.textParagraph("채움 둘"),
                    paragraph,
                    try HwpSynthetic.textParagraph("뒤 문단"),
                ]
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }
            let tail = try XCTUnwrap(Columns.fragments(on: pages[1]).first)
            expect(tail.attributedString?.length) == 31
            expect(tail.frame.height).to(beCloseTo(32, within: 0.5))
            expect(Support.isMarked(try XCTUnwrap(tail.attributedString))).to(beTrue())
            expect(Columns.drawnLineLengths(of: tail)) == [30, 1]
            let follower = try XCTUnwrap(pages[1].blocks.first {
                $0.attributedString?.string.contains("뒤 문단") == true
            })
            // 재배치가 실제로 돌았다 — 뒤 문단은 둘째 단으로 갔다.
            expect(follower.frame.minX).to(beGreaterThan(tail.frame.maxX))
        }

        /// 다시 잰 나머지의 마지막 줄 높이는 조각이 아니라 **문단 전체**의 지표다: 20pt 글자
        /// 하나로 시작하는 10pt 본문(160%)은 줄 피치가 32pt인데, 나머지에는 10pt 글자뿐이라
        /// 조각만 보면 마지막 줄이 16pt로 재어져 상자가 그려지는 줄보다 짧아진다.
        func testRemeasuredRemainderKeepsTheParagraphLineHeightMetrics() async throws {
            let index = HwpIndex(
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
            var paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 91))
            var paraCharShape = CoreHwp.HwpParaCharShape()
            paraCharShape.startingIndex = [0, 1]
            paraCharShape.shapeId = [1, 0]
            paragraph.paraCharShape = paraCharShape
            // 본문 100pt: 좁은 단에 32pt 줄 둘(+ 구역 첫 문단)이 들어가고 나머지가 넓은 단으로 간다.
            let (paginator, _) = try Columns.columns(
                charactersPerLine: [30, 61], contentHeight: 100, bodyParagraphs: [paragraph],
                index: index
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            guard let page = pages.first else { return }
            let fragments = Columns.fragments(on: page)
            expect(fragments.count) == 2
            guard fragments.count == 2 else { return }
            let drawn = Columns.drawnLines(of: fragments[1])
            expect(drawn.count).to(beGreaterThanOrEqualTo(1))
            // 나머지의 마지막 줄은 문단 전체의 32pt로 재어진다(조각만 보면 16pt) — 상자가 줄
            // 피치 32pt 이상이고 그려진 마지막 줄(강제 줄 높이라 ascent 19·descent 13)이 상자에
            // 담긴다. 앞 조각이 #164 규약으로 내준 마지막 줄 ascent 초과분(10pt)은 이 상자에 더
            // 실리므로 정확한 높이는 여기서 고정하지 않는다.
            expect(fragments[1].frame.height)
                .to(beGreaterThanOrEqualTo(CGFloat(drawn.count) * 32 - 0.5))
            let last = try XCTUnwrap(drawn.last)
            expect(last.baselineOrigin.y + last.descent)
                .to(beLessThanOrEqualTo(fragments[1].frame.maxY + 0.5))
        }

        /// 균형 재배치가 문단의 **가운데** 조각(문단 끝을 담지 않음)을 폭이 다른 단으로 옮겨
        /// 다시 잴 때 문단 아래 간격은 싣지 않는다 — 원래 단위 높이도 마지막 줄 단위만 잔여
        /// (아래 간격 포함)를 흡수한다. 3단(30·61·30자)·아래 간격 4pt·9줄 문단: 가운데 단의
        /// 조각(줄 넷~일곱, 120자 → 61자 + 59자)은 32pt, 마지막 단의 조각(31자)은 잔여를 담아
        /// 16 + 16 + 4 = 36pt다.
        func testRebalancedMiddleFragmentExcludesParagraphAfterSpacing() async throws {
            let index = HwpIndex(
                charShapes: [:],
                paraShapes: [0: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingBottom: 800,
                    tabDefId: 0, lineSpacing2: 160
                )],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
            let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 241))
            let (paginator, widths) = try Columns.columns(
                charactersPerLine: [30, 61, 30], contentHeight: 200, bodyParagraphs: [paragraph],
                index: index
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let fragments = Columns.fragments(on: page)
            expect(fragments.map { $0.attributedString?.length }) == [90, 120, 31]
            guard fragments.count == 3 else { return }
            expect(fragments[1].frame.width).to(beCloseTo(widths[1], within: 0.01))
            expect(Columns.drawnLineLengths(of: fragments[1])) == [61, 59]
            expect(fragments[1].frame.height).to(beCloseTo(32, within: 0.5))
            expect(fragments[2].frame.height).to(beCloseTo(36, within: 0.5))
        }

        /// 다시 잰 나머지의 첫 줄 ascent 초과분은 앞 조각의 마지막 줄과 나머지의 마지막 줄 가운데
        /// **작은** ascent 기준이다 — 앞 조각의 마지막 줄만 기준으로 삼으면 그 줄도 개체 줄(ascent
        /// 20)일 때 초과분이 0이 되어, 다시 재며 개체가 첫 줄로 올라온 나머지의 상자가 그 개체를
        /// 못 담는다.
        func testRemeasuredFirstLineExcessUsesTheSmallerReferenceAscent() {
            func line(_ location: Int, baseline: CGFloat, y: CGFloat) -> HwpLineFrame {
                HwpLineFrame(
                    origin: CGPoint(x: 0, y: y), width: 100, baseline: baseline,
                    attributedRange: NSRange(location: location, length: 10)
                )
            }
            var remainder = HwpFragmentRemainder(
                lines: [line(0, baseline: 20, y: 0), line(10, baseline: 9, y: 30), line(20, baseline: 9, y: 46)],
                textHeight: 62, measuredWidth: 100, heightIsMeasured: true
            )
            remainder.place(1)
            // 다시 잰 나머지: 첫 줄이 개체 줄(20), 마지막 줄은 보통 줄(9).
            remainder.replace(
                with: HwpParagraphFrame(
                    totalHeight: 46, lines: [line(0, baseline: 20, y: 0), line(10, baseline: 9, y: 30)]
                ),
                textHeight: 46, width: 150, range: NSRange(location: 10, length: 20)
            )
            expect(remainder.start) == 10
            expect(remainder.lines.map(\.attributedRange.location)) == [10, 20]
            expect(remainder.advances.ascentExcess(startingAt: 0)).to(beCloseTo(11, within: 0.001))
            expect(remainder.advances.precedingBaseline).to(beCloseTo(9, within: 0.001))
            // 문단 머리부터 다시 재면(아무 줄도 안 놓음) 초과분이 없다.
            var whole = HwpFragmentRemainder(
                lines: [line(0, baseline: 20, y: 0), line(10, baseline: 9, y: 30)],
                textHeight: 46, measuredWidth: 100, heightIsMeasured: true
            )
            whole.replace(
                with: HwpParagraphFrame(totalHeight: 30, lines: [line(0, baseline: 20, y: 0)]),
                textHeight: 30, width: 150, range: NSRange(location: 0, length: 20)
            )
            expect(whole.advances.precedingBaseline).to(beNil())
            expect(whole.advances.ascentExcess(startingAt: 0)) == 0
            expect(whole.remeasureCount) == 1
        }
    }
#endif

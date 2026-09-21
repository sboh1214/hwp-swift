import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 1단 흐름 배치에서 남은 자리에 일부 줄만 들어가는 문단의 쪽 나눔 (#207).
    ///
    /// 한글 12.30 실측(2026-09-21, `probes/207`): 외톨이줄 보호가 꺼진 문단은 남은 자리에
    /// 들어가는 줄을 현재 쪽에 남기고 나머지만 다음 쪽으로 넘긴다. 외톨이줄 보호는 경계 양쪽에
    /// 최소 두 줄, 문단 보호는 부분 채운 쪽에서 통째 이동, 문단 위 간격은 첫 줄과 함께 판정하고
    /// 통째로 옮긴 새 쪽 머리에도 든다. 각주는 참조 줄의 쪽에 실리고 그 줄의 적합 판정에 든다.
    ///
    /// 기하: 여백 없는 쪽, 30자/줄, 10pt 160%라 줄 전진량 16pt. 구역 첫 문단(빈 문서 템플릿 줄
    /// 캐시)이 첫 쪽 머리 16pt를 차지한다. 쪽 끝 적합은 줄 전진량으로 재므로(#222는 별개) 본문
    /// 높이는 전진량 합에 여유를 더해 잡는다.
    final class HwpFlowParagraphPageSplitTests: XCTestCase {
        private typealias Support = MeasuredLineFragmentSupport
        private typealias Pages = InlineControlFragmentSupport

        /// 구역 첫 문단이 차지하는 첫 쪽 머리 (빈 문서 템플릿 줄 캐시 1000 + 600 HWPUNIT).
        private static let templateHeight: CGFloat = 16
        private static let linePitch: CGFloat = 16

        /// 문단 모양 id 1: `protection`(표 44 bit 16·18)과 문단 위 간격(HWPUNIT, 표 43의 1/2
        /// 저장 규약이라 2000 → 10pt)을 가진 인덱스. id 0은 기본(보호 없음·간격 0)이다.
        private static func index(
            property1: UInt32 = 0, spacingTop: Int32 = 0
        ) -> HwpIndex {
            HwpIndex(
                charShapes: [:],
                paraShapes: [
                    0: CoreHwp.HwpParaShape(
                        property1: 0, marginLeft: 0, tabDefId: 0, lineSpacing2: 160
                    ),
                    1: CoreHwp.HwpParaShape(
                        property1: property1, marginLeft: 0,
                        paragraphSpacingTop: spacingTop, tabDefId: 0, lineSpacing2: 160
                    ),
                ],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
        }

        /// `lineCount`줄(30자씩) 문단 — 문단 모양 id 1을 참조한다.
        private static func paragraph(lines lineCount: Int) throws -> CoreHwp.HwpParagraph {
            try HwpSynthetic.styledParagraph(
                String(repeating: "가", count: 30 * lineCount), paraShapeId: 1
            )
        }

        private static func isContinued(_ block: AnyHwpBlock) -> Bool? {
            guard let text = block.attributedString, text.length > 0 else { return nil }
            return text.attribute(
                HwpAttributedStringKey.continuedParagraphFragment, at: text.length - 1,
                effectiveRange: nil
            ) != nil
        }

        private struct Layout {
            let pages: [HwpPage]
            /// 쪽마다 본문 문단(서수 1)의 조각 — 없으면 nil.
            let fragments: [AnyHwpBlock?]
            let follower: (page: Int, block: AnyHwpBlock)?

            func lineCount(onPage page: Int) -> Int {
                guard let fragment = fragments[page] else { return 0 }
                return Int(((fragment.frame.height) / linePitch).rounded())
            }
        }

        /// 본문 높이 `contentHeight`의 쪽에 `host`와 뒤 문단을 놓는다. `fillerLines`가 있으면 그
        /// 줄 수의 채움 문단(16pt씩)을 앞에 두어 첫 쪽의 남은 자리를 줄인다 — 한 쪽에는 들어가는
        /// 문단을 첫 쪽에서 통째로 밀어내는 형상에 쓴다.
        private static func layout(
            _ host: CoreHwp.HwpParagraph,
            contentHeight: CGFloat,
            index: HwpIndex = index(),
            fillerLines: Int = 0
        ) async throws -> Layout {
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: host)
            let follower = try HwpSynthetic.textParagraph("뒤 문단")
            let filler = fillerLines > 0
                ? [try HwpSynthetic.textParagraph(String(repeating: "채", count: 30 * fillerLines))]
                : []
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(Support.sectionDef(
                    columnWidth: Support.columnWidth(charactersPerLine: 30, in: built),
                    contentHeight: contentHeight
                ))],
                bodyParagraphs: filler + [host, follower]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let pages = try await Pages.pages(of: paginator)
            let hostIndex = 1 + filler.count
            var followerPlacement: (page: Int, block: AnyHwpBlock)?
            for (pageIndex, page) in pages.enumerated() {
                if let block = page.blocks.first(where: {
                    $0.attributedString?.string.contains("뒤 문단") == true
                }) {
                    followerPlacement = (pageIndex, block)
                    break
                }
            }
            return Layout(
                pages: pages,
                fragments: pages.map { page in
                    page.blocks.first {
                        $0.kind == .text && $0.source?.sectionIndex == 0
                            && $0.source?.paragraphIndex == hostIndex
                    }
                },
                follower: followerPlacement
            )
        }

        /// 조각이 그리는 줄 수 — 한 줄 조각은 측정 줄 조각 표식이 없어(두 줄부터 단다)
        /// `expectDrawsMeasuredLines`를 못 쓴다.
        private static func drawnLineCount(of block: AnyHwpBlock) -> Int {
            guard let text = block.attributedString else { return 0 }
            return HwpDrawnTextLayout.lines(
                attributedString: text, origin: .zero, lineWidth: block.frame.width
            ).count
        }

        // MARK: 보호 없음

        /// 세 줄 문단 가운데 두 줄이 남은 자리에 들어가면 두 줄은 현재 쪽에, 셋째 줄은 다음 쪽에
        /// 놓인다 (한글 실측 A·WE: 첫 줄이 들어가는 만큼만 남긴다).
        func testPartiallyFittingParagraphKeepsTheFittingLinesOnTheCurrentPage() async throws {
            // 남은 자리 40pt: 두 줄(32)은 들어가고 셋째 줄(48)은 아니다.
            let layout = try await Self.layout(
                Self.paragraph(lines: 3), contentHeight: Self.templateHeight + 40
            )
            expect(layout.pages.count) == 2
            guard layout.pages.count == 2 else { return }
            let head = try XCTUnwrap(layout.fragments[0])
            let tail = try XCTUnwrap(layout.fragments[1])
            expect(head.attributedString?.length) == 60
            expect(tail.attributedString?.length) == 30
            expect(head.frame.minY).to(beCloseTo(Self.templateHeight, within: 0.01))
            expect(head.frame.height).to(beCloseTo(32, within: 0.01))
            expect(tail.frame.minY).to(beCloseTo(0, within: 0.01))
            expect(tail.frame.height).to(beCloseTo(16, within: 0.01))
            Support.expectDrawsMeasuredLines(head, lineCount: 2, linePitch: 16)
            expect(Self.drawnLineCount(of: tail)) == 1
            // 앞 조각만 이어짐 표식을 단다 — 양쪽 정렬·문단 끝 상자가 뒤 조각에만 든다.
            expect(Self.isContinued(head)) == true
            expect(Self.isContinued(tail)) == false
            let follower = try XCTUnwrap(layout.follower)
            expect(follower.page) == 1
            expect(follower.block.frame.minY).to(beCloseTo(tail.frame.maxY, within: 0.01))
        }

        /// 문단 전체가 들어가면 나누지 않는다 (한글 실측 Q).
        func testParagraphThatFitsEntirelyStaysWhole() async throws {
            let layout = try await Self.layout(
                Self.paragraph(lines: 3), contentHeight: Self.templateHeight + 48 + 4
            )
            let head = try XCTUnwrap(layout.fragments[0])
            expect(head.attributedString?.length) == 90
            expect(head.frame.height).to(beCloseTo(48, within: 0.01))
            expect(layout.fragments.dropFirst().compactMap { $0 }).to(beEmpty())
        }

        /// 첫 줄조차 안 들어가면 종전대로 문단을 통째로 다음 쪽에서 다시 처리한다 (한글 실측 R)
        /// — 첫 쪽엔 구역 첫 문단과 채움 문단만 남는다.
        func testParagraphWhoseFirstLineDoesNotFitMovesWhole() async throws {
            // 본문 60pt: 템플릿 16 + 채움 두 줄 32 뒤 남은 12pt에 첫 줄(16)이 안 들어간다.
            let layout = try await Self.layout(
                Self.paragraph(lines: 3), contentHeight: 60, fillerLines: 2
            )
            expect(layout.pages.count) >= 2
            guard layout.pages.count >= 2 else { return }
            expect(layout.fragments[0]).to(beNil())
            let whole = try XCTUnwrap(layout.fragments[1])
            expect(whole.attributedString?.length) == 90
            expect(whole.frame.minY).to(beCloseTo(0, within: 0.01))
        }

        /// 한 쪽보다 긴 문단도 부분 채운 쪽에서 시작한다 (한글 실측 O: 첫 줄은 현재 쪽, 나머지는
        /// 다음 쪽부터 이어진다) — 종전엔 빈 쪽으로 옮긴 뒤에야 나눴다.
        func testOversizedParagraphStartsOnThePartiallyFilledPage() async throws {
            // 본문 48pt: 첫 쪽 = 템플릿 16 + 두 줄, 둘째 쪽 = 세 줄(가득), 뒤 문단은 셋째 쪽.
            let layout = try await Self.layout(
                Self.paragraph(lines: 5), contentHeight: 48
            )
            expect(layout.pages.count) == 3
            guard layout.pages.count == 3 else { return }
            expect(layout.fragments[0]?.attributedString?.length) == 60
            expect(layout.fragments[0]?.frame.minY).to(beCloseTo(Self.templateHeight, within: 0.01))
            expect(layout.fragments[1]?.attributedString?.length) == 90
            expect(layout.fragments[1]?.frame.minY).to(beCloseTo(0, within: 0.01))
            expect(layout.fragments[2]).to(beNil())
            expect(layout.follower?.page) == 2
        }

        // MARK: 문단 위 간격

        /// 문단 위 간격은 첫 줄과 함께 판정하고 현재 쪽에서 소비한다 (한글 실측 KB: 간격 12 + 첫 줄
        /// 16이 남은 33.62에 들어 첫 줄이 735.2 = 723.2 + 12에 놓인다). 이어지는 조각 앞에는 없다.
        func testBeforeGapIsChargedWithTheFirstLine() async throws {
            // 남은 34pt: 간격 10 + 첫 줄 16 = 26은 들어가고 둘째 줄(42)은 아니다. 다음 쪽(50pt)엔
            // 두 줄과 뒤 문단이 든다.
            let layout = try await Self.layout(
                Self.paragraph(lines: 3), contentHeight: Self.templateHeight + 34,
                index: Self.index(spacingTop: 2000)
            )
            expect(layout.pages.count) == 2
            guard layout.pages.count == 2 else { return }
            let head = try XCTUnwrap(layout.fragments[0])
            let tail = try XCTUnwrap(layout.fragments[1])
            expect(head.attributedString?.length) == 30
            expect(head.frame.minY).to(beCloseTo(Self.templateHeight + 10, within: 0.01))
            expect(tail.attributedString?.length) == 60
            expect(tail.frame.minY).to(beCloseTo(0, within: 0.01))
        }

        /// 간격 + 첫 줄이 안 들어가면 통째로 옮기고, 새 쪽 머리에도 간격이 든다 (한글 실측 KA:
        /// 새 쪽 첫 줄이 111.2 = 99.2 + 12).
        func testBeforeGapMovesWithTheParagraphToTheNextPage() async throws {
            // 본문 64pt: 템플릿 16 + 채움 두 줄 32 뒤 남은 16pt에 간격 10 + 첫 줄 16 = 26이 안
            // 들어간다. 다음 쪽엔 간격 10 + 세 줄 48이 든다.
            let layout = try await Self.layout(
                Self.paragraph(lines: 3), contentHeight: 64,
                index: Self.index(spacingTop: 2000), fillerLines: 2
            )
            expect(layout.pages.count) >= 2
            guard layout.pages.count >= 2 else { return }
            expect(layout.fragments[0]).to(beNil())
            let whole = try XCTUnwrap(layout.fragments[1])
            expect(whole.attributedString?.length) == 90
            expect(whole.frame.minY).to(beCloseTo(10, within: 0.01))
        }

        // MARK: 외톨이줄 보호 (표 44 bit 16)

        /// 경계 양쪽에 최소 두 줄 — 다섯 줄 문단은 세 줄이 들어가면 3 + 2 (한글 실측 F).
        func testWidowOrphanProtectionSplitsFiveLinesAsThreeAndTwo() async throws {
            let layout = try await Self.layout(
                Self.paragraph(lines: 5), contentHeight: Self.templateHeight + 48 + 4,
                index: Self.index(property1: 1 << 16)
            )
            expect(layout.fragments[0]?.attributedString?.length) == 90
            expect(layout.fragments[1]?.attributedString?.length) == 60
        }

        /// 네 줄 가운데 세 줄이 들어가도 뒤에 두 줄을 남겨 2 + 2 (한글 실측 WC) — 보호가 없으면
        /// 3 + 1이다 (한글 실측 WE).
        func testWidowOrphanProtectionLeavesTwoLinesForTheNextPage() async throws {
            let contentHeight = Self.templateHeight + 48 + 4
            let protected = try await Self.layout(
                Self.paragraph(lines: 4), contentHeight: contentHeight,
                index: Self.index(property1: 1 << 16)
            )
            expect(protected.fragments[0]?.attributedString?.length) == 60
            expect(protected.fragments[1]?.attributedString?.length) == 60
            let unprotected = try await Self.layout(
                Self.paragraph(lines: 4), contentHeight: contentHeight
            )
            expect(unprotected.fragments[0]?.attributedString?.length) == 90
            expect(unprotected.fragments[1]?.attributedString?.length) == 30
        }

        /// 한 줄만 들어가거나(한글 실측 B·WA·T) 세 줄 문단(C: 2 + 1도 뒤가 외톨이)이면 통째로
        /// 다음 쪽 — 한 쪽보다 긴 문단도 첫 줄만 남는 자리면 통째로 옮긴 뒤 새 쪽에서 나뉜다 (V).
        func testWidowOrphanProtectionMovesTheParagraphWhenEitherSideWouldBeAlone() async throws {
            let index = Self.index(property1: 1 << 16)
            // 본문 100pt: 템플릿 16 + 채움 네 줄 64 뒤 남은 20pt에 한 줄만 들어간다.
            let oneLineFits = try await Self.layout(
                Self.paragraph(lines: 5), contentHeight: 100, index: index, fillerLines: 4
            )
            expect(oneLineFits.fragments[0]).to(beNil())
            expect(oneLineFits.fragments[1]?.attributedString?.length) == 150

            let threeLines = try await Self.layout(
                Self.paragraph(lines: 3), contentHeight: Self.templateHeight + 32 + 4, index: index
            )
            expect(threeLines.fragments[0]).to(beNil())
            expect(threeLines.fragments[1]?.attributedString?.length) == 90

            // 본문 36pt(템플릿 뒤 한 줄 자리): 여섯 줄 문단은 새 쪽에서 두 줄씩 나뉜다.
            let oversized = try await Self.layout(
                Self.paragraph(lines: 6), contentHeight: Self.templateHeight + 16 + 4, index: index
            )
            expect(oversized.fragments[0]).to(beNil())
            expect(oversized.fragments[1]?.attributedString?.length) == 60
            expect(oversized.fragments[2]?.attributedString?.length) == 60
            expect(oversized.fragments[3]?.attributedString?.length) == 60
        }

        // MARK: 문단 보호 (표 44 bit 18)

        /// 부분 채운 쪽에서는 나누지 않고 통째로 옮긴다 (한글 실측 J) — 빈 쪽보다 긴 문단은 새
        /// 쪽에서부터 나뉜다 (KD).
        func testKeepLinesTogetherMovesTheParagraphWholeThenSplitsOnlyOversized() async throws {
            let index = Self.index(property1: 1 << 18)
            let twoLinesFit = try await Self.layout(
                Self.paragraph(lines: 3), contentHeight: Self.templateHeight + 32 + 4, index: index
            )
            expect(twoLinesFit.fragments[0]).to(beNil())
            expect(twoLinesFit.fragments[1]?.attributedString?.length) == 90

            // 본문 52pt(세 줄 자리): 다섯 줄 문단은 새 쪽에서 3 + 2.
            let oversized = try await Self.layout(
                Self.paragraph(lines: 5), contentHeight: Self.templateHeight + 32 + 4, index: index
            )
            expect(oversized.fragments[0]).to(beNil())
            expect(oversized.fragments[1]?.attributedString?.length) == 90
            expect(oversized.fragments[2]?.attributedString?.length) == 60
        }

        // MARK: 분할 규칙 표

        /// 한글 실측 표 그대로의 규칙 단위 가드 — (들어가는 줄, 남은 줄) → 남기는 줄.
        func testSplitPolicyTable() {
            let widow = HwpParagraphSplitPolicy(protectsWidowOrphan: true)
            let cases: [(fitting: Int, remaining: Int, expected: Int)] = [
                (1, 3, 0), (2, 3, 0), (1, 2, 0), (1, 4, 0), (2, 4, 2), (3, 4, 2),
                (1, 5, 0), (2, 5, 2), (3, 5, 3), (4, 5, 3), (3, 6, 3), (4, 6, 4),
                (1, 8, 0), (5, 8, 5), (1, 74, 0), (41, 74, 41), (5, 5, 5), (0, 5, 0),
            ]
            for entry in cases {
                expect(widow.allowedCount(
                    fitting: entry.fitting, remaining: entry.remaining, columnIsEmpty: false
                )).to(equal(entry.expected), description: "\(entry.fitting)/\(entry.remaining)")
            }
            let keep = HwpParagraphSplitPolicy(keepsLinesTogether: true)
            expect(keep.allowedCount(fitting: 2, remaining: 3, columnIsEmpty: false)) == 0
            expect(keep.allowedCount(fitting: 3, remaining: 3, columnIsEmpty: false)) == 3
            // 빈 단에서는 문단 보호를 적용하지 않는다 (진행 보장).
            expect(keep.allowedCount(fitting: 41, remaining: 74, columnIsEmpty: true)) == 41
            expect(HwpParagraphSplitPolicy.none.allowedCount(
                fitting: 1, remaining: 3, columnIsEmpty: false
            )) == 1
        }
    }
#endif

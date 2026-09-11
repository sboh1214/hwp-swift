import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 분할된 문단 조각의 줄 수·높이 계약 (#166): 측정한 줄 전진량으로 높이를 잡아 놓은
    /// 조각은 렌더러가 그 줄 수 그대로 그린다 — 문단 전체로는 접히지 않던 두 줄이 조각
    /// 혼자서는 한 줄 넘침 허용 배율(1.06) 안에 들어도 한 줄로 접지 않는다. 접으면 조각
    /// 아래에 접힌 줄만큼 빈 공간이 남는다.
    ///
    /// 재현 입력은 이슈의 것이다: `가` 61자를 폭 `30a + δ`(`a`는 이 글꼴에서 잰 `가` 한
    /// 글자의 자연 폭)에 놓으면 30·30·1자 세 줄로 나뉘고, 뒤 두 줄(31자)의 자연 폭
    /// `31a`는 그 폭의 1.06배 안이다. 세 분할 경로(쪽 경계 흐름 분할·다단 균형 재배치·
    /// 표 행 분할)마다 그 조각이 실제로 만들어지는 문서를 짓는다.
    final class HwpMeasuredLineFragmentTests: XCTestCase {
        private typealias Support = MeasuredLineFragmentSupport

        // MARK: 렌더·측정 공유 술어

        /// 표식을 단 조각은 한 줄 넘침 허용 안에 들어도 측정한 줄바꿈(30자 + 1자) 그대로
        /// 그려지고, 조각을 다시 재는 측정(`layout`)도 같은 줄을 낸다 — 왼쪽·가운데·오른쪽
        /// 정렬 모두. 표식 없는 같은 조각은 한 줄로 접힌다 (수정 전 렌더의 기제).
        func testMarkedFragmentKeepsTheMeasuredLineBreaks() throws {
            for alignment in Support.alignments {
                let index = Support.index(alignment: alignment.rawValue)
                let paragraph = try HwpSynthetic.textParagraph(String(repeating: "가", count: 61))
                let whole = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                    .build(paragraph: paragraph)
                let shape = index.paraShapeOrDefault(for: paragraph)
                let width = Support.columnWidth(charactersPerLine: 30, in: whole)
                let frame = HwpParagraphLayout().layout(
                    attributedString: whole, paraShape: shape, columnWidth: width
                )
                expect(frame.lines.map(\.attributedRange.length))
                    .to(equal([30, 30, 1]), description: alignment.name)
                guard frame.lines.count == 3 else { return }
                let range = NSUnionRange(
                    frame.lines[1].attributedRange, frame.lines[2].attributedRange
                )

                let unmarked = HwpParagraphLayout.continuationFragment(of: whole, range: range)
                let natural = Support.naturalWidth(of: unmarked)
                // 전제: 조각 혼자서는 허용 배율 안에 든다.
                expect(natural / width).to(beGreaterThan(1), description: alignment.name)
                expect(natural / width).to(
                    beLessThan(HwpRenderTuning.Text.slightOverflowWidthRatio),
                    description: alignment.name
                )
                expect(HwpDrawnTextLayout.lines(
                    attributedString: unmarked, origin: .zero, lineWidth: width
                ).count).to(equal(1), description: "\(alignment.name): 표식 없는 조각은 접힌다")

                let marked = HwpParagraphLayout.measuredLineFragment(
                    unmarked, heightIsMeasured: true, measuredLineCount: 2,
                    measuredWidth: width, columnWidth: width
                )
                expect(Support.isMarked(marked)).to(beTrue(), description: alignment.name)
                expect(marked.attribute(
                    HwpAttributedStringKey.measuredLineFragment, at: marked.length - 1,
                    effectiveRange: nil
                )).toNot(beNil(), description: "\(alignment.name): 표식은 조각 전체에 붙는다")
                expect(HwpDrawnTextLayout.slightOverflowLineMetrics(
                    attributedString: marked, lineWidth: width
                )).to(beNil(), description: alignment.name)
                let expected = [NSRange(location: 0, length: 30), NSRange(location: 30, length: 1)]
                expect(HwpDrawnTextLayout.lines(
                    attributedString: marked, origin: .zero, lineWidth: width
                ).map(\.stringRange)).to(equal(expected), description: alignment.name)
                expect(HwpParagraphLayout().layout(
                    attributedString: marked, paraShape: shape, columnWidth: width
                ).lines.map(\.attributedRange)).to(equal(expected), description: alignment.name)
            }
        }

        /// 한 줄 조각에는 표식이 없다 — 문단 전체 블록의 한 줄은 한 줄 넘침 규칙으로 접혀 잰
        /// 것일 수 있어(31자가 30자 폭에서 한 줄) 표식이 두 줄로 되돌리고, 잘라낸 한 줄은 잰 폭에
        /// 들어가 표식이 렌더를 바꾸지 못한다. 캐시 높이 조각(`heightIsMeasured` false)과 빈
        /// 조각도 표식이 없고, 표식이 있던 입력은 벗겨진다.
        func testSingleLineFragmentIsNotMarked() throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let whole = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: try HwpSynthetic.textParagraph(String(repeating: "가", count: 31)))
            let width = Support.columnWidth(charactersPerLine: 30, in: whole)
            let shape = index.paraShapeOrDefault(for: try HwpSynthetic.textParagraph(""))
            // 전제: 문단 전체는 한 줄 넘침 규칙으로 한 줄로 재어진다.
            expect(HwpParagraphLayout().layout(
                attributedString: whole, paraShape: shape, columnWidth: width
            ).lines.count) == 1
            for columnWidth in [width, width * 2, width - 0.4] {
                let full = HwpParagraphLayout.measuredLineFragment(
                    whole, heightIsMeasured: true, measuredLineCount: 1,
                    measuredWidth: width, columnWidth: columnWidth
                )
                expect(Support.isMarked(full)).to(beFalse(), description: "\(columnWidth)")
                expect(HwpDrawnTextLayout.lines(
                    attributedString: full, origin: .zero, lineWidth: columnWidth
                ).count).to(equal(1), description: "\(columnWidth)")
            }
            let premarked = NSMutableAttributedString(attributedString: whole)
            premarked.addAttribute(
                HwpAttributedStringKey.measuredLineFragment, value: NSNumber(value: true),
                range: NSRange(location: 0, length: premarked.length)
            )
            expect(Support.isMarked(HwpParagraphLayout.measuredLineFragment(
                premarked, heightIsMeasured: true, measuredLineCount: 1,
                measuredWidth: width, columnWidth: width
            ))).to(beFalse())
            expect(Support.isMarked(HwpParagraphLayout.measuredLineFragment(
                premarked, heightIsMeasured: false, measuredLineCount: 2,
                measuredWidth: width, columnWidth: width
            ))).to(beFalse())
            expect(HwpParagraphLayout.measuredLineFragment(
                NSAttributedString(), heightIsMeasured: true, measuredLineCount: 2,
                measuredWidth: width, columnWidth: width
            ).length) == 0
        }

        /// 좁아진 단의 판정은 폭 허용 오차 없는 실제 줄바꿈이다 (PR 리뷰): 잰 폭(b 70자에 0.1pt
        /// 여유)에서 "a " / "b×70 " 두 줄인 조각(뒤에 c×70 줄이 이어지는 문단의 앞 두 줄)을
        /// **0.3pt** 좁은 단에 놓으면 렌더러는 한 줄 넘침 규칙으로 접을 수 있지만(자연 폭 73자
        /// ≤ 1.06배), 표식을 달아 접지 않고 그리면 b 줄이 다시 나뉘어 세 줄이 되어 두 줄 상자를
        /// 넘친다 — 그러면 표식을 달지 않는다. 0.5pt 허용 오차로 같은 폭이라 보면 이 조각에
        /// 표식이 붙는다. 잰 폭 그대로면 줄이 늘 수 없으므로 단다.
        func testNarrowerColumnMarksOnlyWhenTheUnfoldedLinesFitTheMeasuredCount() throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let paragraph = try HwpSynthetic.textParagraph(
                "a " + String(repeating: "b", count: 70) + " " + String(repeating: "c", count: 70)
            )
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: paragraph)
            let glyph = Support.naturalWidth(
                of: built.attributedSubstring(from: NSRange(location: 2, length: 1))
            )
            // 잰 폭: b 70자가 0.1pt 여유로 들어가고 "a b…"는 넘쳐 "a "가 첫 줄이 된다.
            let measuredWidth = 70 * glyph + 0.1
            let frame = HwpParagraphLayout().layout(
                attributedString: built, paraShape: index.paraShapeOrDefault(for: paragraph),
                columnWidth: measuredWidth
            )
            expect(frame.lines.prefix(2).map(\.attributedRange.length)) == [2, 71]
            guard frame.lines.count >= 2 else { return }
            let range = NSUnionRange(frame.lines[0].attributedRange, frame.lines[1].attributedRange)
            let fragment = HwpParagraphLayout.continuationFragment(of: built, range: range)
            let narrower = measuredWidth - 0.3
            // 전제: 좁은 단에서 조각은 접힘 대상이고, 접지 않고 그리면 세 줄이다.
            expect(HwpDrawnTextLayout.slightOverflowLineMetrics(
                attributedString: fragment, lineWidth: narrower
            )).toNot(beNil())
            let forced = NSMutableAttributedString(attributedString: fragment)
            forced.addAttribute(
                HwpAttributedStringKey.measuredLineFragment, value: NSNumber(value: true),
                range: NSRange(location: 0, length: forced.length)
            )
            expect(HwpDrawnTextLayout.lines(
                attributedString: forced, origin: .zero, lineWidth: narrower
            ).count) == 3
            let atNarrower = HwpParagraphLayout.measuredLineFragment(
                fragment, heightIsMeasured: true, measuredLineCount: 2,
                measuredWidth: measuredWidth, columnWidth: narrower
            )
            expect(Support.isMarked(atNarrower)).to(beFalse())
            expect(HwpDrawnTextLayout.lines(
                attributedString: atNarrower, origin: .zero, lineWidth: narrower
            ).count) == 1
            let atMeasured = HwpParagraphLayout.measuredLineFragment(
                fragment, heightIsMeasured: true, measuredLineCount: 2,
                measuredWidth: measuredWidth, columnWidth: measuredWidth
            )
            expect(Support.isMarked(atMeasured)).to(beTrue())
            expect(HwpDrawnTextLayout.lines(
                attributedString: atMeasured, origin: .zero, lineWidth: measuredWidth
            ).count) == 2
        }

        // MARK: 쪽 경계 흐름 분할

        /// 라인 캐시 없는 문단이 쪽에 걸쳐 나뉘면(`appendLineSliceBlock`) 뒤 조각(30자 + 1자)은
        /// 측정한 두 줄 높이로 놓이고 렌더러도 두 줄을 그린다 — 뒤 문단은 그 바로 아래다.
        func testFlowPageSplitFragmentDrawsAsManyLinesAsItWasMeasured() async throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let host = try HwpSynthetic.textParagraph(String(repeating: "가", count: 121))
            let follower = try HwpSynthetic.textParagraph("뒤 문단")
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: host)
            // 본문 높이 56pt = 줄 전진량(16pt) 3.5줄 — 앞 조각 줄 셋, 뒤 조각 줄 둘(30자 + 1자)과
            // 뒤 문단이 다음 쪽에 들어간다.
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(Support.sectionDef(
                    columnWidth: Support.columnWidth(charactersPerLine: 30, in: built),
                    contentHeight: 56
                ))],
                bodyParagraphs: [host, follower]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            // 흐름 배치는 구역 첫 문단 뒤에 안 들어가는 긴 문단을 새 쪽으로 옮긴다 — 쪽 3장.
            expect(pages.count) == 3
            guard pages.count == 3 else { return }
            let head = try XCTUnwrap(InlineControlFragmentSupport.hostFragment(on: pages[1]))
            let tail = try XCTUnwrap(InlineControlFragmentSupport.hostFragment(on: pages[2]))
            expect(head.attributedString?.length) == 90
            expect(tail.attributedString?.length) == 31
            Support.expectDrawsMeasuredLines(head, lineCount: 3, linePitch: 16)
            Support.expectDrawsMeasuredLines(tail, lineCount: 2, linePitch: 16)
            let followerBlock = try XCTUnwrap(pages[2].blocks.first {
                $0.attributedString?.string.contains("뒤 문단") == true
            })
            expect(followerBlock.frame.minY).to(beCloseTo(tail.frame.maxY, within: 0.01))
        }

        // MARK: 다단 균형 재배치

        /// 첫 단에 다 들어간 문단을 밴드를 닫으며 줄 단위로 두 단에 나누면
        /// (`HwpColumnBandController.balancedBlocks`) 뒤 단 조각(30자 + 1자)은 줄 둘의 높이로
        /// 놓이고 렌더러도 두 줄을 그린다.
        func testColumnBalanceFragmentDrawsAsManyLinesAsItWasMeasured() async throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let host = try HwpSynthetic.textParagraph(String(repeating: "가", count: 121))
            let follower = try HwpSynthetic.textParagraph("뒤 문단")
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: host)
            let columnWidth = Support.columnWidth(charactersPerLine: 30, in: built)
            // 등폭 2단(간격 10pt): 본문 높이 120pt라 문단 다섯 줄(80pt)과 뒤 문단이 첫 단에 다
            // 들어가고, 밴드를 닫으며 줄 단위 균형 재배치가 줄 넷·다섯과 뒤 문단을 뒤 단에 놓는다.
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(Support.sectionDef(
                        columnWidth: columnWidth * 2 + 10, contentHeight: 120
                    )),
                    .column(HwpSynthetic.column(count: 2, spacing: 1000)),
                ],
                bodyParagraphs: [host, follower]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 1
            guard let page = pages.first else { return }
            let fragments = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("가") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(fragments.map { $0.attributedString?.length }) == [90, 31]
            guard fragments.count == 2 else { return }
            expect(fragments[1].frame.minX)
                .to(beCloseTo(fragments[0].frame.maxX + 10, within: 0.05))
            Support.expectDrawsMeasuredLines(fragments[0], lineCount: 3, linePitch: 16)
            Support.expectDrawsMeasuredLines(fragments[1], lineCount: 2, linePitch: 16)
            let followerBlock = try XCTUnwrap(page.blocks.first {
                $0.attributedString?.string.contains("뒤 문단") == true
            })
            expect(followerBlock.frame.minX).to(beCloseTo(fragments[1].frame.minX, within: 0.01))
            expect(followerBlock.frame.minY).to(beCloseTo(fragments[1].frame.maxY, within: 0.01))
        }

        // MARK: 표 행 분할

        /// 표 행이 쪽에 걸쳐 나뉘면(`HwpTableSplitter.paragraphFragment`) 셀 문단의 뒤 조각
        /// (30자 + 1자)은 측정한 두 줄 높이로 놓이고 렌더러도 두 줄을 그린다.
        func testTableRowSplitFragmentDrawsAsManyLinesAsItWasMeasured() async throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            // 일곱 줄(30자 × 6 + 1자) — 행 높이 112pt.
            let cell = try HwpSynthetic.textParagraph(String(repeating: "가", count: 181))
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: cell)
            var host = try HwpSynthetic.textParagraph("")
            host.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 20000, rowHeights: [1000], cellParagraphs: [[[cell]]]
            ))]
            // 본문 높이 88pt: 빈 쪽에도 안 들어가는 행이라 새 쪽(둘째 쪽)에서 줄 다섯(80pt)을
            // 자르고 나머지 줄 둘(30자 + 1자)을 셋째 쪽으로 이월한다.
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(Support.sectionDef(
                    columnWidth: Support.columnWidth(charactersPerLine: 30, in: built),
                    contentHeight: 88
                ))],
                bodyParagraphs: [host]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 3
            guard pages.count == 3 else { return }
            let head = try XCTUnwrap(Support.cellFragments(on: pages[1]).first)
            let tail = try XCTUnwrap(Support.cellFragments(on: pages[2]).first)
            expect(head.text.length) == 150
            expect(tail.text.length) == 31
            Support.expectDrawsMeasuredLines(tail.text, in: tail.rect, lineCount: 2, linePitch: 16)
            Support.expectDrawsMeasuredLines(head.text, in: head.rect, lineCount: 5, linePitch: 16)
        }
    }

    /// `HwpMeasuredLineFragmentTests` 입력·오라클.
    enum MeasuredLineFragmentSupport {
        /// 문단 모양 속성1 bits 2-4의 정렬 (1 왼쪽, 2 오른쪽, 3 가운데).
        struct Alignment {
            let name: String
            let rawValue: UInt32
        }

        static let alignments = [
            Alignment(name: "왼쪽", rawValue: 1),
            Alignment(name: "가운데", rawValue: 3),
            Alignment(name: "오른쪽", rawValue: 2),
        ]

        /// 지정한 정렬의 문단 모양 하나(id 0)만 가진 인덱스 — 줄 간격은 기본 160%다.
        static func index(alignment: UInt32) -> HwpIndex {
            HwpIndex(
                charShapes: [:],
                paraShapes: [0: CoreHwp.HwpParaShape(
                    property1: alignment << 2, marginLeft: 0, tabDefId: 0, lineSpacing2: 160
                )],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
        }

        static func naturalWidth(of attributedString: NSAttributedString) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(attributedString), nil, nil, nil
            ))
        }

        /// 첫 글자 `n`개는 들어가고 `n + 1`개는 안 들어가는 단 폭 — 글자 자연 폭 `a`의 `n`배에
        /// 0.75pt를 더한다. `n + 1`자 조각(자연 폭 `(n + 1)a`)이 한 줄 넘침 허용 안에 들려면
        /// `(n + 1)a ≤ 1.06(na + 0.75)`여야 한다 — 여유를 무시하면 `n ≥ 17`, 10pt 글리프면
        /// `n ≥ 16`. 이 파일은 `n = 30`(비율 ≈ 1.03)을 쓴다.
        static func columnWidth(
            charactersPerLine count: Int, in built: NSAttributedString
        ) -> CGFloat {
            CGFloat(count) * characterAdvance(in: built) + 0.75
        }

        /// 조판 문자열 첫 글자(`가`)의 자연 폭 `a`.
        static func characterAdvance(in built: NSAttributedString) -> CGFloat {
            naturalWidth(of: built.attributedSubstring(from: NSRange(location: 0, length: 1)))
        }

        /// 여백 없는 구역 정의 — 단 폭·본문 높이를 pt로 준다 (HWPUNIT 올림).
        static func sectionDef(
            columnWidth: CGFloat, contentHeight: CGFloat
        ) -> CoreHwp.HwpSectionDef {
            var sectionDef = HwpSynthetic.sectionDef(
                pageWidth: UInt32((columnWidth * 100).rounded(.up)),
                pageHeight: UInt32((contentHeight * 100).rounded(.up))
            )
            sectionDef.pageDef.marginLeft = 0
            sectionDef.pageDef.marginRight = 0
            sectionDef.pageDef.marginTop = 0
            sectionDef.pageDef.marginBottom = 0
            sectionDef.pageDef.marginGutter = 0
            return sectionDef
        }

        static func isMarked(_ attributedString: NSAttributedString) -> Bool {
            HwpDrawnTextLayout.isMeasuredLineFragment(attributedString)
        }

        /// 그 쪽 표 블록 안의 셀 문단 조각(`가`를 담은 것)과 쪽 좌표 rect.
        static func cellFragments(
            on page: HwpPage
        ) -> [(text: NSAttributedString, rect: CGRect)] {
            var fragments: [(text: NSAttributedString, rect: CGRect)] = []
            for block in page.blocks where block.kind == .table {
                HwpBlockContentWalker.walkText(block: block) { attributed, rect, _ in
                    guard attributed.string.contains("가") else { return }
                    fragments.append((attributed, rect))
                }
            }
            return fragments
        }

        static func expectDrawsMeasuredLines(
            _ block: AnyHwpBlock, lineCount: Int, linePitch: CGFloat,
            file: FileString = #filePath, line: UInt = #line
        ) {
            guard let text = block.attributedString else {
                fail("텍스트 블록이 아니다", file: file, line: line)
                return
            }
            expectDrawsMeasuredLines(
                text, in: block.frame, lineCount: lineCount, linePitch: linePitch,
                file: file, line: line
            )
        }

        /// 조각의 계약: 표식이 있고, 렌더러가 측정한 줄 수만큼 그리며, 마지막 줄이 조각 상자의
        /// 마지막 줄 자리에 놓여 아래에 줄 하나가 통째로 비지 않는다. 상자 높이는 줄 전진량 합이다.
        static func expectDrawsMeasuredLines(
            _ text: NSAttributedString, in frame: CGRect, lineCount: Int, linePitch: CGFloat,
            file: FileString = #filePath, line: UInt = #line
        ) {
            expect(file: file, line: line, isMarked(text)).to(beTrue(), description: "측정 줄 조각 표식")
            expect(file: file, line: line, frame.height)
                .to(beCloseTo(CGFloat(lineCount) * linePitch, within: 0.5), description: "조각 높이")
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: text, origin: frame.origin, lineWidth: frame.width
            )
            expect(file: file, line: line, drawn.count)
                .to(equal(lineCount), description: "그려지는 줄 수")
            guard let last = drawn.last else { return }
            expect(file: file, line: line, last.baselineOrigin.y)
                .to(beGreaterThan(frame.maxY - linePitch), description: "마지막 줄이 상자 마지막 줄 자리")
            expect(file: file, line: line, last.baselineOrigin.y + last.descent)
                .to(beLessThanOrEqualTo(frame.maxY + 0.5), description: "마지막 줄이 상자 안")
        }
    }
#endif

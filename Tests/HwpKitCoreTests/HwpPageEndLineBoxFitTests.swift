import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽·단 끝 적합 판정은 줄 **상자** 하단까지다 (#222).
    ///
    /// 한글 12.30 실측(2026-09-21·24, `probes/206`·`probes/222`, 줄 캐시 없는 합성 HWPX를 한글이
    /// 다시 저장한 `linesegarray`와 PDF): 마지막으로 남기는 줄의 상자 하단이 본문 하단보다 **위**면
    /// 그 줄을 남기고, 줄 간격 여분과 문단 아래 간격은 쪽 아래로 넘쳐도 된다 — 남은 17.62pt에
    /// 16pt·160% 줄(상자 16, 전진량 25.6)은 남고 18pt 줄은 넘어간다. 상자 하단이 본문 하단과
    /// **같으면** 넘긴다(17.62pt 줄은 넘기고 17.61pt 줄은 남긴다 — 줄 간격 100%라도 같다). 고정 줄
    /// 간격이 상자보다 작은 줄도 상자로 판정한다(상자 10·전진량 8인 줄을 남은 9pt에서 넘긴다).
    /// 넘친 여분은 다음 쪽으로 이월하지 않는다 — 다음 문단은 새 쪽 상단에서 시작한다.
    ///
    /// 기하: 여백 없는 쪽, 30자/줄. 구역 첫 문단(빈 문서 템플릿 줄 캐시)이 첫 쪽 머리 16pt를,
    /// 채움 문단이 줄마다 16pt(10pt·160%)를 차지하고 본문 높이는 그 뒤 남은 자리로 정한다.
    final class HwpPageEndLineBoxFitTests: XCTestCase {
        private typealias Support = MeasuredLineFragmentSupport

        /// 글자 모양 id → 기본 크기 (HWPUNIT).
        private static let charSizes: [UInt32: Int32] = [
            0: 1000, 1: 1600, 2: 1800, 3: 1762, 4: 1761, 5: 2000,
        ]

        /// 문단 모양 id 0은 기본(160%), 1은 `shape`다.
        private static func index(shape: CoreHwp.HwpParaShape? = nil) throws -> HwpIndex {
            var paraShapes: [UInt32: CoreHwp.HwpParaShape] = [
                0: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, tabDefId: 0, lineSpacing2: 160
                ),
            ]
            paraShapes[1] = shape
            return HwpIndex(
                charShapes: try charSizes.mapValues(
                    HwpNumberingHeadingRenderTests.charShape(baseSize:)
                ),
                paraShapes: paraShapes,
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:]
            )
        }

        /// 비율 160% 문단 모양 — 속성1(쪽 나눔 보호 비트)·아래 간격(HWPUNIT, 1/2 저장 규약).
        private static func percentShape(
            property1: UInt32 = 0, spacingBottom: Int32 = 0
        ) -> CoreHwp.HwpParaShape {
            CoreHwp.HwpParaShape(
                property1: property1, marginLeft: 0, paragraphSpacingBottom: spacingBottom,
                tabDefId: 0, lineSpacing2: 160
            )
        }

        /// 고정 줄 간격 문단 모양 — `points`pt (1/2 단위로 저장).
        private static func fixedShape(points: CGFloat) -> CoreHwp.HwpParaShape {
            CoreHwp.HwpParaShape(
                hwpxProperty1: 0, marginLeft: 0, marginRight: 0, indent: 0,
                paragraphSpacingTop: 0, paragraphSpacingBottom: 0, lineSpacing: 0, tabDefId: 0,
                numberingOrBulletId: 0, borderFillId: 0,
                borderSpacingLeft: 0, borderSpacingRight: 0,
                borderSpacingTop: 0, borderSpacingBottom: 0,
                property3: CoreHwp.HwpLineSpacingKind.fixed.rawValue,
                lineSpacing2: UInt32((points * 200).rounded())
            )
        }

        /// 글자 모양 `charShapeId`·문단 모양 1의 대상 문단.
        private static func target(
            _ text: String, charShapeId: UInt32 = 0
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = try HwpSynthetic.styledParagraph(text, paraShapeId: 1)
            var charShape = CoreHwp.HwpParaCharShape()
            charShape.startingIndex = [0]
            charShape.shapeId = [charShapeId]
            paragraph.paraCharShape = charShape
            return paragraph
        }

        struct Layout {
            let pages: [HwpPage]
            /// 쪽마다 대상 문단의 블록.
            let targets: [[AnyHwpBlock]]
            /// 뒤 문단이 놓인 쪽과 블록.
            let follower: (page: Int, block: AnyHwpBlock)?

            /// 대상 문단의 블록이 처음 놓인 쪽.
            var targetPage: Int? {
                targets.firstIndex { !$0.isEmpty }
            }
        }

        /// 첫 쪽에 `remaining`pt를 남기고 대상 문단과 뒤 문단을 놓는다 — 구역 첫 문단 16 + 채움
        /// `fillerLines`줄. `columns`가 2면 두 단(간격 10pt)이고 남은 자리는 첫 단의 것이다.
        static func layout(
            _ target: CoreHwp.HwpParagraph,
            remaining: CGFloat,
            index: HwpIndex,
            fillerLines: Int = 1,
            columns: Int = 1,
            divider: Bool = false
        ) async throws -> Layout {
            let filler = try HwpSynthetic.textParagraph(
                (1 ... fillerLines).map { "채움 \($0)" }.joined(separator: "\n")
            )
            let reference = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: try HwpSynthetic.textParagraph("가"))
            let columnWidth = Support.columnWidth(charactersPerLine: 30, in: reference)
            let contentHeight = 16 + 16 * CGFloat(fillerLines) + remaining
            var controls: [CoreHwp.HwpCtrlId] = [.section(Support.sectionDef(
                columnWidth: columnWidth * CGFloat(columns) + 10 * CGFloat(columns - 1),
                contentHeight: contentHeight
            ))]
            if columns > 1 {
                var column = HwpSynthetic.column(count: columns, spacing: 1000)
                column.dividerType = divider ? 1 : 0
                column.dividerThickness = 1
                controls.append(.column(column))
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: controls,
                bodyParagraphs: [filler, target, try HwpSynthetic.textParagraph("뒤 문단")]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            var follower: (page: Int, block: AnyHwpBlock)?
            for (pageIndex, page) in pages.enumerated() where follower == nil {
                if let block = page.blocks.first(where: {
                    $0.attributedString?.string.contains("뒤 문단") == true
                }) {
                    follower = (pageIndex, block)
                }
            }
            return Layout(
                pages: pages,
                targets: pages.map { page in
                    page.blocks.filter {
                        $0.kind == .text && $0.source?.sectionIndex == 0
                            && $0.source?.paragraphIndex == 2
                    }
                },
                follower: follower
            )
        }

        // MARK: 한 줄 문단

        /// 한글 X1·W1: 남은 17.62에 16pt 줄(상자 16, 전진량 25.6)은 남고 18pt 줄(상자 18)은
        /// 넘어간다. 남긴 줄의 여분은 이월하지 않아 뒤 문단이 다음 쪽 상단에서 시작한다.
        func testLineWhoseBoxFitsStaysEvenIfItsSpacingDoesNot() async throws {
            let index = try Self.index(shape: Self.percentShape())
            let kept = try await Self.layout(
                Self.target("X1", charShapeId: 1), remaining: 17.62, index: index
            )
            expect(kept.targetPage) == 0
            expect(kept.targets.first?.first?.frame.minY).to(beCloseTo(32, within: 0.001))
            expect(kept.targets.first?.first?.frame.height).to(beCloseTo(25.6, within: 0.001))
            expect(kept.follower?.page) == 1
            expect(kept.follower?.block.frame.minY).to(beCloseTo(0, within: 0.001))

            let moved = try await Self.layout(
                Self.target("W1", charShapeId: 2), remaining: 17.62, index: index
            )
            expect(moved.targetPage) == 1
            expect(moved.targets[1].first?.frame.minY).to(beCloseTo(0, within: 0.001))
        }

        /// 한글 EQ·EA·EB: 상자 하단이 본문 하단에 닿으면 넘긴다 — 17.62pt 줄은 남은 17.62에서
        /// 넘어가고(줄 간격 100%라 전진량까지 같아도) 17.61pt 줄은 남는다.
        func testLineBoxTouchingTheBodyBottomMovesOn() async throws {
            let percent = try Self.index(shape: Self.percentShape())
            let touching = try await Self.layout(
                Self.target("EQ", charShapeId: 3), remaining: 17.62, index: percent
            )
            expect(touching.targetPage) == 1
            let inside = try await Self.layout(
                Self.target("EA", charShapeId: 4), remaining: 17.62, index: percent
            )
            expect(inside.targetPage) == 0
            var single = Self.percentShape()
            single.lineSpacing2 = 100
            let singleSpaced = try Self.index(shape: single)
            let exact = try await Self.layout(
                Self.target("EB", charShapeId: 3), remaining: 17.62, index: singleSpaced
            )
            expect(exact.targetPage) == 1
        }

        /// 한글 FX·ED: 고정 줄 간격(8pt)이 상자(10pt)보다 작아도 판정은 상자다 — 남은 9pt에서
        /// 넘기고(전진량 8은 들어가는데) 남은 10.01pt에서 남긴다.
        func testFixedSpacingBelowTheLineBoxIsJudgedByTheBox() async throws {
            let index = try Self.index(shape: Self.fixedShape(points: 8))
            let moved = try await Self.layout(Self.target("FX"), remaining: 9, index: index)
            expect(moved.targetPage) == 1
            let kept = try await Self.layout(Self.target("ED"), remaining: 10.01, index: index)
            expect(kept.targetPage) == 0
        }

        /// 한글 AA·AB: 문단 아래 간격(20pt)은 판정에 들지 않는다 — 상자 10만 들어가면 남고,
        /// 블록은 전진량 + 아래 간격만큼 본문 아래로 넘친다.
        func testParagraphSpacingBelowMayHangBelowTheBody() async throws {
            let index = try Self.index(shape: Self.percentShape(spacingBottom: 4000))
            let layout = try await Self.layout(Self.target("AA"), remaining: 17.62, index: index)
            expect(layout.targetPage) == 0
            let block = try XCTUnwrap(layout.targets.first?.first)
            expect(block.frame.height).to(beCloseTo(36, within: 0.001))
            expect(block.frame.maxY).to(beGreaterThan(32 + 17.62))
            expect(layout.follower?.page) == 1
            expect(layout.follower?.block.frame.minY).to(beCloseTo(0, within: 0.001))
        }

        /// 빈 문단도 줄 상자로 판정한다 — 페이지네이터가 빈 문단 앵커의 줄 프레임을 비우므로
        /// 상자를 따로 잰다 (쪽 끝의 빈 줄은 흔하다). 상자 10은 남은 12에 들고 10에는 안 든다.
        func testEmptyParagraphIsJudgedByItsLineBox() async throws {
            let index = try Self.index(shape: Self.percentShape())
            let kept = try await Self.layout(Self.target(""), remaining: 12, index: index)
            expect(kept.follower?.page) == 1
            let keptPages = kept.pages.count
            let moved = try await Self.layout(Self.target(""), remaining: 10, index: index)
            expect(moved.follower?.page) == 1
            // 남긴 빈 문단은 뒤 문단만 다음 쪽 상단으로 보내고, 넘긴 빈 문단은 다음 쪽에서 한 줄을
            // 차지해 뒤 문단이 그 아래다.
            expect(kept.follower?.block.frame.minY).to(beCloseTo(0, within: 0.001))
            expect(moved.follower?.block.frame.minY).to(beCloseTo(16, within: 0.001))
            expect(keptPages) == 2
        }

        /// 줄 캐시 높이를 쓰는 문단은 판정도 캐시의 줄 상자(`vertsize`)로 한다 — 높이와 같은 출처.
        /// 캐시 상자 12pt(CT 상자 10pt)는 남은 11에서 넘어가고 12.5에서 남는다.
        func testCachedParagraphIsJudgedByItsCachedLineBox() async throws {
            let index = try Self.index(shape: Self.percentShape())
            func cached() throws -> CoreHwp.HwpParagraph {
                var paragraph = try HwpSynthetic.lineSegParagraph(
                    "캐시", segments: [(location: 0, height: 1200)]
                )
                paragraph.paraHeader = try HwpSynthetic.outlineParaHeader(
                    paraShapeId: 1, paraStyleId: 0
                )
                return paragraph
            }
            let moved = try await Self.layout(cached(), remaining: 11, index: index)
            expect(moved.targetPage) == 1
            let kept = try await Self.layout(cached(), remaining: 12.5, index: index)
            expect(kept.targetPage) == 0
        }

        // MARK: 여러 줄 문단

        /// 한글 PL·Z1: 여러 줄 문단은 상자가 들어가는 줄까지 남긴다 — 남은 44.62에 10pt 세 줄
        /// (마지막 줄 상자 바닥 16 + 16 + 10 = 42)은 통째로 남고, 남은 17.62에 16pt 여러 줄
        /// 문단은 첫 줄(상자 16)만 남는다.
        func testMultiLineParagraphKeepsEveryLineWhoseBoxFits() async throws {
            let index = try Self.index(shape: Self.percentShape())
            let whole = try await Self.layout(
                Self.target(String(repeating: "가", count: 90)), remaining: 44.62, index: index
            )
            expect(whole.targets.map(\.count)) == [1, 0]
            expect(whole.targets.first?.first?.frame.height).to(beCloseTo(48, within: 0.001))
            expect(whole.follower?.page) == 1

            let split = try await Self.layout(
                Self.target(String(repeating: "가", count: 60), charShapeId: 1),
                remaining: 17.62, index: index
            )
            expect(split.targetPage) == 0
            expect(split.targets.first?.first?.frame.height).to(beCloseTo(25.6, within: 0.001))
            expect(split.targets.count).to(beGreaterThanOrEqualTo(2))
            expect(split.targets[1].first?.frame.minY).to(beCloseTo(0, within: 0.001))
        }

        /// 한글 KL: 문단 보호 세 줄도 상자가 모두 들어가면 남는다(남은 44.62) — 마지막 줄 상자
        /// 바닥이 안 들어가면(남은 41.62) 통째로 넘어간다.
        func testKeepLinesTogetherParagraphStaysWhenEveryBoxFits() async throws {
            let index = try Self.index(shape: Self.percentShape(property1: 1 << 18))
            let text = String(repeating: "가", count: 90)
            let kept = try await Self.layout(Self.target(text), remaining: 44.62, index: index)
            expect(kept.targets.map(\.count)) == [1, 0]
            let moved = try await Self.layout(Self.target(text), remaining: 41.62, index: index)
            expect(moved.targets.first).to(beEmpty())
            expect(moved.targets[1].first?.frame.height).to(beCloseTo(48, within: 0.001))
        }

        /// 한글 WB: 외톨이줄 보호는 상자로 센 줄 수에 걸린다 — 남은 49.62에 16pt 줄은 둘
        /// (25.6 + 상자 16 = 41.6)이 들어가 2 + 나머지로 나뉜다(전진량으로 세면 한 줄이라 통째).
        func testWidowOrphanProtectionCountsTheLinesWhoseBoxesFit() async throws {
            let index = try Self.index(shape: Self.percentShape(property1: 1 << 16))
            let layout = try await Self.layout(
                Self.target(String(repeating: "가", count: 100), charShapeId: 1),
                remaining: 49.62, index: index
            )
            expect(layout.targetPage) == 0
            expect(layout.targets.first?.first?.frame.height).to(beCloseTo(51.2, within: 0.001))
            let rest = layout.targets.dropFirst().flatMap { $0 }
            expect(rest.map(\.frame.height).reduce(0, +)).to(beGreaterThanOrEqualTo(51.2))
        }

        // MARK: 다단

        /// 한글 CX: 단 끝도 같은 규칙이다 — 첫 단의 남은 17.62에 16pt 한 줄이 남고 뒤 문단이
        /// 둘째 단 머리에서 시작한다.
        func testColumnEndKeepsTheLineWhoseBoxFits() async throws {
            let index = try Self.index(shape: Self.percentShape())
            let layout = try await Self.layout(
                Self.target("CX", charShapeId: 1), remaining: 17.62, index: index, columns: 2
            )
            let block = try XCTUnwrap(layout.targets.first?.first)
            expect(block.frame.minX).to(beCloseTo(0, within: 0.001))
            expect(block.frame.minY).to(beCloseTo(32, within: 0.001))
            let follower = try XCTUnwrap(layout.follower)
            expect(follower.page) == 0
            expect(follower.block.frame.minX).to(beGreaterThan(block.frame.maxX))
            expect(follower.block.frame.minY).to(beCloseTo(0, within: 0.001))
        }

        /// 한글 DA: 단 구분선은 단 끝 문단의 줄 **상자** 바닥에서 끝난다 — 아래 간격 20pt는 들지
        /// 않는다(쪽 끝 적합이 줄 상자까지라 그 간격이 본문 아래로 넘친 단에서도 같다).
        func testColumnDividerEndsAtTheLastLineBoxNotItsParagraphSpacing() async throws {
            let index = try Self.index(shape: Self.percentShape(spacingBottom: 4000))
            let layout = try await Self.layout(
                Self.target("DA"), remaining: 17.62, index: index, columns: 2, divider: true
            )
            let block = try XCTUnwrap(layout.targets.first?.first)
            expect(block.frame.height).to(beCloseTo(36, within: 0.001))
            let divider = try XCTUnwrap(layout.pages.first?.blocks.first {
                $0.kind == .shape && $0.role == .pageChrome
            })
            expect(divider.frame.maxY).to(beCloseTo(block.frame.minY + 10, within: 0.01))
        }
    }
#endif

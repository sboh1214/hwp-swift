import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 저장본 줄 캐시 높이로 놓는 문단의 쪽 끝 적합 판정 (#222 PR 리뷰) — 렌더러는 캐시 높이 블록
    /// 안에서도 줄을 **CT 전진량**으로 그리므로(`HwpDrawnTextLayout.lines`), 문단 전체를 남길지는
    /// 마지막 줄만 캐시 상자 바닥으로 재고 앞 줄들은 그려지는 CT 상자로 잰다. 캐시 상자 바닥만 보면
    /// CT 줄 상자가 캐시보다 큰 문단(MS 워드 호환 문서의 글꼴 대체, 글자보다 낮은 낡은 캐시)을 통째로
    /// 두어 그 뒤 줄이 본문 아래·쪽 밖에 그려진다.
    final class HwpPageEndFitCacheExtentTests: XCTestCase {
        private typealias Fit = HwpPageEndLineBoxFitTests

        /// MS 워드 호환 문서에서 CT 줄 상자(글꼴 상자)가 신선한 10pt 캐시(12pt 피치 네 줄, 상자 바닥
        /// 46)보다 크면 캐시로는 들어가는 자리라도 나눈다 — 첫 쪽에 그려진 줄이 모두 쪽 안에 있고
        /// 나머지가 다음 쪽이다. 캐시 바닥만 보면 통째로 두어 셋째 줄이 쪽 끝에 걸치고 넷째 줄은 쪽 밖에
        /// 그려졌다. 쪽 높이는 문단 머리 위치와 CT 상자 판정값을 먼저 재어 캐시 바닥과 그 사이로 잡는다.
        func testFreshCacheWithLargerCTFontBoxesKeepsDrawnLinesOnThePage() async throws {
            let index = Self.msWordIndex()
            let paragraph = try HwpSynthetic.splitParagraphWithNoteMarkers(
                lines: (0 ..< 4).map { _ in (characters: 3, marker: false) },
                segments: [(0, 1000, 0), (1200, 1000, 4), (2400, 1000, 8), (3600, 1000, 12)]
            )
            let cachedExtent: CGFloat = 36 + 10
            let cachedHeight: CGFloat = 36 + 10 + 6
            // CT 줄 상자로 잰 판정값 — 캐시 바닥보다 확실히 커야 이 테스트가 뜻이 있다.
            let attributed = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: paragraph)
            let lines = HwpParagraphLayout().layout(
                attributedString: attributed, paraShape: index.paraShapeOrDefault(for: paragraph),
                columnWidth: 400
            ).lines
            expect(lines.count) == 4
            let ctFit = HwpFragmentLineAdvances(
                lines: lines, textHeight: cachedHeight, cachedLastLineBoxBottom: cachedExtent
            ).fitHeight(from: 0, through: lines.count - 1)
            expect(ctFit).to(beGreaterThan(cachedExtent + 2))
            // 문단 머리 위치 — 넉넉한 쪽에서 잰다.
            let roomy = try await Self.blocks(of: paragraph, index: index, pageHeight: 1000)
            let top = try XCTUnwrap(roomy.first?.first).frame.minY
            let pageHeight = top + (cachedExtent + ctFit) / 2
            let tight = try await Self.blocks(of: paragraph, index: index, pageHeight: pageHeight)
            let head = try XCTUnwrap(tight.first?.first)
            let drawn = MeasuredLineRemeasureSupport.drawnLines(of: head)
            expect(drawn.count) < 4
            for line in drawn {
                expect(line.baselineOrigin.y + line.descent).to(beLessThanOrEqualTo(pageHeight))
            }
            expect(tight.dropFirst().first?.isEmpty) == false
        }

        /// 캐시 줄 높이보다 큰 글자를 선언한 낡은 캐시(16pt 글자·10pt 캐시 — 한글이 열 때 다시 조판한다)도
        /// 앞 줄의 CT 상자로 잰다 — 16pt·160% 세 줄(CT 상자 아래 16·41.6·67.2)은 남은 38에서 1 + 2로
        /// 나뉜다. 캐시 바닥(34)만 보면 통째로 두어 셋째 줄이 쪽 밖에 그려졌다.
        func testGlyphStaleCacheKeepsItsCTBoxesInTheWholeParagraphFit() async throws {
            var paragraph = try HwpSynthetic.splitParagraphWithNoteMarkers(
                lines: (0 ..< 3).map { _ in (characters: 3, marker: false) },
                segments: [(0, 1000, 0), (1200, 1000, 4), (2400, 1000, 8)]
            )
            paragraph.paraHeader = try HwpSynthetic.outlineParaHeader(
                paraShapeId: 1, paraStyleId: 0
            )
            var runs = CoreHwp.HwpParaCharShape()
            runs.startingIndex = [0]
            runs.shapeId = [1] // 16pt
            paragraph.paraCharShape = runs
            let layout = try await Fit.layout(
                paragraph, remaining: 38, index: Fit.index(shape: Fit.percentShape())
            )
            expect(layout.targets.map(\.count).prefix(2)) == [1, 1]
            let first = try XCTUnwrap(layout.targets.first?.first)
            expect(first.frame.minY).to(beCloseTo(32, within: 0.001))
            expect(first.frame.height).to(beCloseTo(25.6, within: 0.001))
        }

        /// 글자 모양 0(10pt)·문단 모양 0(160%)의 MS 워드 호환 문서 색인.
        private static func msWordIndex() -> HwpIndex {
            HwpIndex(
                charShapes: [0: CoreHwp.HwpCharShape(
                    faceId: [0, 0, 0, 0, 0, 0, 0], faceSpacing: [0, 0, 0, 0, 0, 0, 0],
                    baseSize: 1000, faceColor: CoreHwp.HwpColor()
                )],
                paraShapes: [0: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingTop: 0, paragraphSpacingBottom: 0,
                    lineSpacing: 160, tabDefId: 0, lineSpacing2: 160
                )],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:],
                isCompatibilityDocument: true,
                compatibleDocumentTarget: .msWord
            )
        }

        /// 여백 없는 400pt 폭·`pageHeight` 높이 쪽에 문단 하나를 놓아 쪽마다 그 문단의 블록.
        private static func blocks(
            of paragraph: CoreHwp.HwpParagraph, index: HwpIndex, pageHeight: CGFloat
        ) async throws -> [[AnyHwpBlock]] {
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(MeasuredLineFragmentSupport.sectionDef(
                    columnWidth: 400, contentHeight: pageHeight
                ))],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index, fontResolver: .testDeterministic
            )
            return try await InlineControlFragmentSupport.pages(of: paginator).map { page in
                page.blocks.filter { $0.kind == .text && $0.source?.paragraphIndex == 1 }
            }
        }
    }
#endif

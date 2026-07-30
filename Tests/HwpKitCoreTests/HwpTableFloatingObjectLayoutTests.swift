@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 셀 안 개체가 셀 높이에 어떻게 반영되는지 (#91).
    ///
    /// 규약 요약: 셀 문단 전부가 라인 캐시로 측정되면 저작된 셀 높이 (표 80)를
    /// 신뢰하는데, 그 신뢰는 **줄 상자에 들어가는 개체까지만** 성립한다.
    /// 문단 기준으로 떠 있는 개체는 캐시에도 저작 높이에도 없어 별도 하한이
    /// 필요하고 (`HwpTableLayout.floatingObjectHeight`), 쪽/종이 기준 개체는
    /// 그 하한에서 제외한다 (`HwpParagraphObjectCollector.growsContainer`).
    final class HwpTableFloatingObjectLayoutTests: XCTestCase {
        /// 셀 안 **떠 있는** 개체는 한글 줄 캐시에도 저작된 셀 높이 (표 80)에도
        /// 없다 — 그 둘만 믿으면 행이 라벨 한 줄로 접히고 개체가 아래 행들을
        /// 덮으며 표 밖으로 흘러나간다 (#91: noori 3쪽 붙임 표가 선언 627.0pt의
        /// 29%인 181.6pt로 조판됐다. 형상 행은 저작 12.82pt·캐시 16.00pt인데
        /// 셀 안 그림이 455.40pt다).
        func testFloatingObjectInCellGrowsRowBeyondAuthoredHeight() throws {
            // noori 형상 행 재현: 저작 10pt·캐시 16pt인데 떠 있는 개체는 300pt
            var floating = try HwpSynthetic.lineSegParagraph(
                "", segments: [(location: 0, height: 1000)]
            )
            floating.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.floatingShapeObject(width: 5000, height: 30000)),
            ]
            let result = layout().layout(
                table: try shapeRowTable(shapeParagraph: floating),
                availableWidth: 400,
                index: index()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            // 형상 행은 개체 높이만큼 자라고 (여백 0), 다음 행은 저작대로 남는다.
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(300, within: 0.5))
            expect(frame.rows[1].rowFrame.height).to(beCloseTo(10, within: 0.5))
            // 개체가 자기 셀 안에 들어온다 — 이 이슈의 증상이 바로 이 초과였다.
            let shapeCell = frame.rows[0].cells[1]
            expect(shapeCell.shapes.count) == 1
            expect(shapeCell.shapes.first?.rect.maxY ?? .infinity)
                <= shapeCell.cellFrame.maxY + 0.5
        }

        /// 반대 방향 가드: **글자처럼 취급** 개체는 줄 캐시가 담는 몫이라
        /// 하한을 얹지 않는다. 얹으면 캐시를 신뢰하는 규약 (헌법주석 실측 —
        /// 셀이 저작 높이보다 부풀면 페이지 분할이 한글과 어긋난다)이 깨진다.
        func testInlineObjectInCellKeepsAuthoredRowHeight() throws {
            var inline = try HwpSynthetic.lineSegParagraph(
                "", segments: [(location: 0, height: 1000)]
            )
            inline.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 5000, height: 30000)),
            ]
            let result = layout().layout(
                table: try shapeRowTable(shapeParagraph: inline),
                availableWidth: 400,
                index: index()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(10, within: 0.5))
        }

        /// 쪽/종이 기준 개체는 하한에서 뺀다. 그 저작 세로 오프셋은 **페이지 상단
        /// 기준 절대 좌표**인데 컨테이너 안에는 쪽 기하가 없어 `origin()`이
        /// 문단 rect에 그대로 더하는 근사를 쓴다 (R32 #3). 근사를 높이 하한으로
        /// 승격시키면 위치 오차가 표 총높이·페이지 분할 오차로 번진다 —
        /// 여기 오프셋 600pt가 하한이 되면 행이 10pt에서 700pt로 뛴다.
        func testPageAnchoredFloatingObjectDoesNotGrowRow() throws {
            var anchored = try HwpSynthetic.lineSegParagraph(
                "", segments: [(location: 0, height: 1000)]
            )
            anchored.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.floatingShapeObject(
                    width: 5000, height: 10000,
                    verticalRelativeTo: .paper, verticalOffset: 60000
                )),
            ]
            let result = layout().layout(
                table: try shapeRowTable(shapeParagraph: anchored),
                availableWidth: 400,
                index: index()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            expect(frame.rows[0].rowFrame.height).to(beCloseTo(10, within: 0.5))
        }

        /// 글 뒤로·글 앞으로는 **겹치는 것이 설계**라 (앵커 규칙 "text 블록과
        /// 겹칠 수 있음") 담으려고 셀을 키우지 않는다 — 셀 안 워터마크·말풍선
        /// 하나가 행을 부풀려 표 총높이와 페이지 분할을 함께 어긋낸다.
        /// 빠지는 것은 **높이 하한뿐**이고 셀 콘텐츠 배치는 그대로여야 한다
        /// (하한에서 빼려다 개체를 통째로 잃으면 소실 회귀다).
        func testOverlayWrapModesDoNotGrowRowButStayRendered() throws {
            for wrap in [CoreHwp.HwpCommonCtrlTextWrap.behindText, .inFrontOfText] {
                var overlay = try HwpSynthetic.lineSegParagraph(
                    "", segments: [(location: 0, height: 1000)]
                )
                overlay.ctrlHeaderArray = [
                    .genShapeObject(HwpSynthetic.floatingShapeObject(
                        width: 5000, height: 30000, textWrap: wrap
                    )),
                ]
                let result = layout().layout(
                    table: try shapeRowTable(shapeParagraph: overlay),
                    availableWidth: 400,
                    index: index()
                )

                guard case let .success(frame) = result else {
                    fail("expected table layout success (\(wrap))")
                    return
                }
                expect(frame.rows[0].rowFrame.height).to(beCloseTo(10, within: 0.5))
                expect(frame.rows[0].cells[1].shapes.count) == 1
            }
        }

        /// 측정 (`floatingObjectHeight`)과 배치 (`laidOutContents`)가 문단을 같은
        /// 순서·같은 간격으로 쌓는지 — 셀-로컬 좌표에서 손으로 복제된 유일한
        /// 산술이라 갈리면 개체가 셀을 넘긴다. 앞 문단 텍스트·문단 위 간격·
        /// 중첩 표 전진을 한 셀에 모아 세 팔을 모두 태운다.
        func testFloatingObjectAfterStackedContentStaysInsideCell() throws {
            var floating = try HwpSynthetic.lineSegParagraph(
                "", segments: [(location: 0, height: 1000)]
            )
            floating.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.floatingShapeObject(width: 5000, height: 30000)),
            ]
            // 앞 문단: 텍스트 + 중첩 표 (문단 위 간격은 indexWithSpacing이 준다)
            var leading = try HwpSynthetic.lineSegParagraph(
                "앞", segments: [(location: 0, height: 1000)]
            )
            leading.ctrlHeaderArray = [.table(HwpSynthetic.table(
                cellWidth: 4000,
                rowHeights: [1000],
                cellParagraphs: [[[try HwpSynthetic.lineSegParagraph(
                    "중첩", segments: [(location: 0, height: 1000)]
                )]]]
            ))]
            let table = HwpSynthetic.table(
                cellWidth: 10000,
                rowHeights: [1000, 1000],
                cellParagraphs: [
                    [[try labelledParagraph("형 상")], [leading, floating]],
                    [[try labelledParagraph("총 길이")], [try labelledParagraph("47.2 m")]],
                ]
            )
            let result = layout().layout(
                table: table, availableWidth: 400, index: indexWithSpacing()
            )

            guard case let .success(frame) = result else {
                fail("expected table layout success")
                return
            }
            let shapeCell = frame.rows[0].cells[1]
            expect(shapeCell.shapes.count) == 1
            // 개체가 앞 문단·간격·중첩 표만큼 내려갔는데도 셀 안에 담긴다.
            expect(shapeCell.shapes.first?.rect.minY ?? 0) > shapeCell.cellFrame.minY + 10
            expect(shapeCell.shapes.first?.rect.maxY ?? .infinity)
                <= shapeCell.cellFrame.maxY + 0.5
        }

        /// 형상 행 + 값 행 2×2 표 — 모든 셀이 라인 캐시를 갖고 저작 높이는 10pt다
        /// (`hasCachedContent && authoredHeight > 0` 분기를 타게 한다).
        private func shapeRowTable(
            shapeParagraph: CoreHwp.HwpParagraph
        ) throws -> CoreHwp.HwpTable {
            HwpSynthetic.table(
                cellWidth: 10000,
                rowHeights: [1000, 1000],
                cellParagraphs: [
                    [[try labelledParagraph("형 상")], [shapeParagraph]],
                    [[try labelledParagraph("총 길이")], [try labelledParagraph("47.2 m")]],
                ]
            )
        }

        private func labelledParagraph(_ text: String) throws -> CoreHwp.HwpParagraph {
            try HwpSynthetic.lineSegParagraph(text, segments: [(location: 0, height: 1000)])
        }

        /// 문단 위/아래 간격이 0이 아닌 index — `halfSpacingBefore` 팔이 측정과
        /// 배치 양쪽에서 실제로 돌게 한다 (기본 index는 간격이 0이라 그 팔이
        /// 갈려도 티가 안 난다).
        private func indexWithSpacing() -> HwpIndex {
            index(extraParaShapes: [0: CoreHwp.HwpParaShape(
                property1: 0,
                marginLeft: 0,
                paragraphSpacingTop: 800,
                paragraphSpacingBottom: 400,
                tabDefId: 0,
                lineSpacing2: 160
            )])
        }
    }

    private extension HwpTableFloatingObjectLayoutTests {
        func layout() -> HwpTableLayout {
            HwpTableLayout(fontResolver: .testDeterministic)
        }

        func index(extraParaShapes: [UInt32: CoreHwp.HwpParaShape] = [:]) -> HwpIndex {
            let paraShape = CoreHwp.HwpParaShape(
                property1: 0,
                marginLeft: 0,
                tabDefId: 0,
                lineSpacing2: 160
            )
            return HwpIndex(
                charShapes: [:],
                paraShapes: [0: paraShape].merging(extraParaShapes) { _, new in new },
                borderFills: [:],
                tabDefs: [:],
                styles: [:],
                bullets: [:],
                numberings: [:],
                binData: [:],
                faceNamesKorean: [:],
                faceNamesEnglish: [:],
                faceNamesChinese: [:],
                faceNamesJapanese: [:],
                faceNamesEtc: [:],
                faceNamesSymbol: [:],
                faceNamesUser: [:]
            )
        }
    }

#endif

import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 줄 상자보다 **작은** 글자처럼 취급 개체의 세로 자리 (#195).
    ///
    /// 개체의 바깥 상자(개체 + 바깥 여백)는 그 높이의 글자 하나처럼 놓인다 — 바깥 상자 상단에서
    /// 높이 × `HwpLineFrame.objectBaselineRatio` 내려간 자리가 줄 베이스라인에 맞는다. 한글
    /// 문서는 글자 상자와 같은 0.85, MS 워드 호환 문서는 1(바깥 상자 바닥이 베이스라인)이다.
    /// 종전에는 두 문서 모두 바깥 상자 **바닥**을 베이스라인에 두어 한글 문서의 작은 개체가
    /// (1 − 0.85) × 높이만큼 위에 그려졌다 (이슈: 함초롬바탕 40pt 줄의 20pt 그림 −2.99pt, 30pt
    /// −4.55pt). 개체가 상자를 정한 줄(코퍼스의 전부)은 변화가 없다.
    ///
    /// 오라클은 한컴오피스 한글 12.30.0 (macOS, 2026-09-21)이 합성 HWPX를 열어 내보낸 PDF의
    /// 그림 상단·표 테두리·텍스트 베이스라인이다 (`HwpObjectAnchorGeometry.inlineAnchorOrigin`
    /// 문서 주석의 표본 — 그림 4~50pt·바깥 여백·상대 크기·줄 간격·글꼴·표·도형·글상자·셀 안·
    /// 쪽에 걸친 문단, 한글 문서와 MS 워드 호환 문서 각각, 전부 0.12pt 안).
    final class HwpInlineObjectBaselineTests: XCTestCase {
        private static let ratio = HwpRenderTuning.Text.baselineAnchorRatio

        // MARK: 줄 지표

        /// 줄 지표가 문서 모델별 비율을 낸다 — 한글 문서는 글자 상자의 0.85, MS 워드 호환 문서는 1.
        func testLineMetricsReportTheObjectBaselineRatioOfTheDocumentModel() {
            let hangul = LineBoxFixtures.attributes(size: 40)
            var msWord = hangul
            msWord[HwpAttributedStringKey.compatibleDocumentTarget] = NSNumber(
                value: HwpCompatibleDocumentTarget.msWord.rawValue
            )
            for (attributes, expected) in [(hangul, Self.ratio), (msWord, CGFloat(1))] {
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(string: "가나", attributes: attributes)
                )
                expect(HwpDrawnTextLayout.lineMetrics(of: line).inlineObjectBaselineRatio)
                    == expected
            }
            // 측정 줄 프레임도 같은 값을 싣는다 — 손으로 만든 프레임의 기본값은 한글 문서 비율.
            let frame = HwpParagraphLayout().layout(
                attributedString: NSAttributedString(string: "가나", attributes: msWord),
                paraShape: CoreHwp.HwpParaShape(), columnWidth: 200
            )
            expect(frame.lines.first?.objectBaselineRatio) == 1
            let manual = HwpLineFrame(
                origin: .zero, width: 10, baseline: 8.5,
                attributedRange: NSRange(location: 0, length: 1)
            )
            expect(manual.objectBaselineRatio) == Self.ratio
        }

        // MARK: 페이지 경로

        /// 40pt 줄(앵커 34)의 20pt 개체 — 상단이 베이스라인 − 0.85 × 20 = 줄 상자 상단 + 17이다
        /// (종전 +14). 한글 실측: `A3 p20` 그림 상단 = 베이스라인 − 16.93.
        func testSmallInlineObjectSitsAtItsOwnBaselineRatio() async throws {
            let placed = try await Self.place(objectHeight: 2000)
            expect(placed.baseline).to(beCloseTo(placed.host.minY + 34, within: 0.01))
            expect(placed.object.minY)
                .to(beCloseTo(placed.baseline - Self.ratio * 20, within: 0.01))
            expect(placed.object.height).to(beCloseTo(20, within: 0.01))
            // 4·8·30pt도 같은 규칙 (한글 실측 3.49·6.85·25.57 위).
            for height in [CGFloat(4), 8, 30] {
                let other = try await Self.place(objectHeight: UInt32(height * 100))
                expect(other.object.minY).to(
                    beCloseTo(other.baseline - Self.ratio * height, within: 0.01),
                    description: "\(height)pt"
                )
            }
        }

        /// 바깥 여백은 바깥 상자에 든다 — 20pt 개체 + 위 7·아래 3의 바깥 30pt 상자가 베이스라인
        /// − 25.5에, 개체는 그 아래 7이라 베이스라인 − 18.5다 (한글 실측 `B1 m7-3` 18.50, `B2
        /// m0-10` 25.59, `B3 m10-0` 15.51). 바깥 상자가 줄 상자보다 크면(위·아래 15 → 50) 상자를
        /// 정하므로 개체 상단 = 줄 상단 + 15 (한글 실측 `B4` 27.48 = 42.5 − 15).
        func testOuterMarginsJoinTheObjectGlyphBox() async throws {
            for (margins, drop) in [
                ([CoreHwp.HWPUNIT16(0), 0, 700, 300], CGFloat(25.5 - 7)),
                ([0, 0, 0, 1000], 25.5),
                ([0, 0, 1000, 0], 25.5 - 10),
            ] {
                let placed = try await Self.place(objectHeight: 2000, margins: margins)
                expect(placed.object.minY).to(
                    beCloseTo(placed.baseline - drop, within: 0.01), description: "\(margins)"
                )
            }
            let oversized = try await Self.place(objectHeight: 2000, margins: [0, 0, 1500, 1500])
            expect(oversized.baseline).to(beCloseTo(oversized.host.minY + 42.5, within: 0.01))
            expect(oversized.object.minY).to(beCloseTo(oversized.host.minY + 15, within: 0.01))
        }

        /// 상자를 정한 60pt 개체는 종전과 같다 — 상단 = 줄 상자 상단, 베이스라인 = 상단 + 51.
        func testTallInlineObjectStillPinsToTheLineBoxTop() async throws {
            let placed = try await Self.place(objectHeight: 6000)
            expect(placed.object.minY).to(beCloseTo(placed.host.minY, within: 0.01))
            expect(placed.baseline).to(beCloseTo(placed.host.minY + Self.ratio * 60, within: 0.01))
        }

        /// MS 워드 호환 문서는 바깥 상자 **바닥**이 베이스라인이다 — 20pt 개체는 베이스라인 −
        /// 20(한글 실측 `A3` 19.93), 위 7·아래 3 여백이면 바깥 바닥이 베이스라인이라 개체 바닥은
        /// 베이스라인 − 3(실측 23.05 = 20 + 3), 상자를 정한 60pt 개체는 베이스라인 = 60이라
        /// 상단 = 줄 상단.
        func testMsWordObjectOuterBoxBottomSitsOnTheBaseline() async throws {
            let plain = try await Self.place(objectHeight: 2000, msWord: true)
            expect(plain.object.maxY).to(beCloseTo(plain.baseline, within: 0.01))
            let margined = try await Self.place(
                objectHeight: 2000, margins: [0, 0, 700, 300], msWord: true
            )
            expect(margined.object.maxY).to(beCloseTo(margined.baseline - 3, within: 0.01))
            let tall = try await Self.place(objectHeight: 6000, msWord: true)
            expect(tall.object.minY).to(beCloseTo(tall.host.minY, within: 0.01))
            expect(tall.baseline).to(beCloseTo(tall.host.minY + 60, within: 0.01))
        }

        // MARK: 컨테이너 경로 (표 셀)

        /// 표 셀 문단의 글자처럼 취급 그림도 같은 산식이다 (`HwpParagraphObjectCollector`,
        /// 한글 실측 `S1 cell` 16.93·`S2` 6.85) — MS 워드 호환 문서면 바닥이 베이스라인.
        func testCellInlinePictureSitsAtItsOwnBaselineRatio() throws {
            for (msWord, drop) in [(false, Self.ratio * 20), (true, CGFloat(20))] {
                let cell = try Self.cell(objectHeight: 2000, msWord: msWord)
                let image = try XCTUnwrap(cell.images.first?.rect)
                let paragraph = try XCTUnwrap(cell.paragraphs.first)
                let line = try XCTUnwrap(paragraph.frame.lines.first)
                let baseline = paragraph.rect.minY + line.origin.y + line.baseline
                expect(image.minY).to(
                    beCloseTo(baseline - drop, within: 0.01), description: "msWord \(msWord)"
                )
                expect(image.height).to(beCloseTo(20, within: 0.01))
            }
            let small = try Self.cell(objectHeight: 800, msWord: false)
            let image = try XCTUnwrap(small.images.first?.rect)
            let paragraph = try XCTUnwrap(small.paragraphs.first)
            let line = try XCTUnwrap(paragraph.frame.lines.first)
            expect(image.minY).to(beCloseTo(
                paragraph.rect.minY + line.origin.y + line.baseline - Self.ratio * 8, within: 0.01
            ))
        }

        // MARK: 조각 경로 (쪽에 걸친 문단)

        /// 쪽 경계로 나뉜 문단의 뒤 조각에 든 작은 개체도 자기 줄의 베이스라인 − 0.85 × 높이에
        /// 놓인다 — 조각 줄 프레임(`fragmentLineFrames`)이 비율을 함께 옮긴다 (한글 실측: 4쪽에
        /// 걸친 40pt 문단의 뒤쪽 20pt 그림 16.94 위). 여기서는 15pt 캐시 줄의 5pt 개체.
        func testSmallObjectInALaterFragmentKeepsTheRatio() async throws {
            let host = try InlineControlFragmentSupport.splitHost(controls: [
                .genShapeObject(HwpSynthetic.inlineShapeObject(
                    width: 3000, height: 500, instanceId: 11
                )),
                .genShapeObject(HwpSynthetic.inlineShapeObject(
                    width: 3000, height: 500, instanceId: 12
                )),
            ])
            let paginator = try InlineControlFragmentSupport.absolutePaginator(host: host)
            let pages = try await InlineControlFragmentSupport.pages(of: paginator)
            expect(pages.count) == 2
            guard pages.count == 2 else { return }
            for (pageIndex, instanceId) in [(0, UInt32(11)), (1, 12)] {
                let page = pages[pageIndex]
                let controlIndex = pageIndex
                let object = try XCTUnwrap(
                    InlineControlFragmentSupport.objectBlocks(on: page, instanceId: instanceId)
                        .first
                )
                let fragment = try XCTUnwrap(InlineControlFragmentSupport.hostFragment(on: page))
                let attributed = try XCTUnwrap(fragment.attributedString)
                let marker = try XCTUnwrap(InlineControlFragmentSupport.drawnMarker(
                    in: attributed, origin: fragment.frame.origin,
                    lineWidth: fragment.frame.width, controlIndex: controlIndex
                ))
                expect(object.frame.height).to(beCloseTo(5, within: 0.01))
                expect(object.frame.minY).to(
                    beCloseTo(marker.baselineY - Self.ratio * 5, within: 0.01),
                    description: "instance \(instanceId)"
                )
            }
        }

        // MARK: 헬퍼

        private struct Placed {
            let object: CGRect
            let host: CGRect
            /// 호스트 문단 첫 줄의 그려지는 베이스라인 y
            let baseline: CGFloat
        }

        /// 글자 모양 0 = 40pt, 문단 모양 0 = 비율 160%. `msWord`면 MS 워드 호환 문서.
        private static func index(msWord: Bool) -> HwpIndex {
            HwpIndex(
                charShapes: [0: CoreHwp.HwpCharShape(
                    faceId: [0, 0, 0, 0, 0, 0, 0], faceSpacing: [0, 0, 0, 0, 0, 0, 0],
                    baseSize: 4000, faceColor: CoreHwp.HwpColor()
                )],
                paraShapes: [0: CoreHwp.HwpParaShape(
                    property1: 0, marginLeft: 0, paragraphSpacingTop: 0, paragraphSpacingBottom: 0,
                    lineSpacing: 160, tabDefId: 0, lineSpacing2: 160
                )],
                borderFills: [:], tabDefs: [:], styles: [:], bullets: [:], numberings: [:],
                binData: [:], faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:], faceNamesUser: [:],
                isCompatibilityDocument: msWord,
                compatibleDocumentTarget: msWord ? .msWord : nil
            )
        }

        /// `가▢나` 문단 (글자 모양 0) — 컨트롤은 `object`.
        private static func host(_ object: CoreHwp.HwpGenShapeObject) -> CoreHwp.HwpParagraph {
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: "가", suffix: "나")
            var shapes = CoreHwp.HwpParaCharShape()
            shapes.startingIndex = [0]
            shapes.shapeId = [0]
            paragraph.paraCharShape = shapes
            paragraph.ctrlHeaderArray = [.genShapeObject(object)]
            return paragraph
        }

        /// 페이지 경로 — 40pt 줄에 폭 40pt·높이 `objectHeight`(HWPUNIT) 도형을 글자처럼 놓는다.
        private static func place(
            objectHeight: UInt32,
            margins: [CoreHwp.HWPUNIT16] = [0, 0, 0, 0],
            msWord: Bool = false
        ) async throws -> Placed {
            var object = HwpSynthetic.inlineShapeObject(width: 4000, height: objectHeight)
            object.commonCtrlProperty.marginArray = margins
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [host(object)]
            )
            let paginator = HwpPaginator(
                sections: [section], index: index(msWord: msWord),
                fontResolver: .testDeterministic
            )
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)
            let body = page.blocks.filter { $0.role == .body }
            let shape = try XCTUnwrap(body.first { $0.kind == .shape })
            let hostBlock = try XCTUnwrap(body.last {
                $0.kind == .text && ($0.attributedString?.string.contains("가") ?? false)
            })
            let attributed = try XCTUnwrap(hostBlock.attributedString)
            let line = try XCTUnwrap(HwpDrawnTextLayout.lines(
                attributedString: attributed, origin: hostBlock.frame.origin,
                lineWidth: hostBlock.frame.width
            ).first)
            return Placed(
                object: shape.frame, host: hostBlock.frame, baseline: line.baselineOrigin.y
            )
        }

        /// 컨테이너 경로 — 40pt 셀 문단에 폭 40pt·높이 `objectHeight`(HWPUNIT) 그림.
        private static func cell(objectHeight: UInt32, msWord: Bool) throws -> HwpTableCellFrame {
            let table = HwpSynthetic.table(
                cellWidth: 30000, rowHeights: [8000], property: 0,
                cellParagraphs: [[[host(HwpSynthetic.inlinePictureObject(
                    width: 4000, height: objectHeight, binItemId: 1
                ))]]]
            )
            let result = HwpTableLayout(fontResolver: .testDeterministic).layout(
                table: table, availableWidth: 400, index: index(msWord: msWord)
            )
            guard case let .success(frame) = result else { throw LayoutFailure() }
            return try XCTUnwrap(frame.rows.first?.cells.first)
        }

        private struct LayoutFailure: Error {}
    }
#endif

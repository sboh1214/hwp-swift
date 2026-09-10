import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 각주 이어짐 (#165) PR 리뷰가 잡은 **본문 하한·앞 조각 적합** 결함의 재현 — 전부 수정 전에
    /// 실패했고 실물 코퍼스(헌법주석)엔 없는 형상이라 합성으로만 잠근다. 경계·개체·식별·모양
    /// 결함은 `HwpFootnoteContinuationReviewTests`(클래스 본문이 SwiftLint type_body_length
    /// 상한에 닿아 갈라 뒀다), 조립 헬퍼는 `FootnoteContinuationSupport`.
    final class HwpFootnoteContinuationBodyBottomTests: XCTestCase {
        private typealias Support = FootnoteContinuationSupport

        /// stale 캐시(캐시 줄 높이 < 글자 크기) 문단이 쪽의 마지막 본문이면 그 블록은 CT
        /// 높이로 커지는데, 커진 몫을 마지막 줄의 줄 간격으로 잘못 기록하면 본문 하한이
        /// 캐시 잉크 아래로 되돌아가 각주 구분선이 커진 글자 위에 그어진다 (#165 리뷰).
        func testStaleCacheGrowthIsNotSubtractedFromTheBodyBottom() async throws {
            // 세 줄, 캐시 줄 높이 5pt(10pt 글자보다 작다 → stale) — CT는 48pt로 다시 조판된다.
            var host = try HwpSynthetic.splitParagraphWithMixedMarkers(
                lines: [
                    (characters: 5, markers: []),
                    (characters: 5, markers: []),
                    (characters: 5, markers: [17]),
                ],
                segments: [
                    (location: 60000, height: 500, textStart: 0),
                    (location: 61100, height: 500, textStart: 6),
                    (location: 62200, height: 500, textStart: 12),
                ]
            )
            // 스택은 바닥 정렬이라 잘못된 하한이 드러나려면 각주가 그 자리를 다 채워야
            // 한다 — 여덟 줄(91.04pt)은 캐시 잉크 기준 자리(101pt)엔 들어가고 CT 기준
            // 자리(80pt)엔 안 들어간다.
            let lines = (1 ... 8).map { "줄 \($0)" }
            host.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [try Support.note(
                    lines: lines, locations: (0 ..< 8).map { Int32($0 * 1172) }
                )]
            ))]
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))
            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)
            let page = try XCTUnwrap(firstPage)
            // 구역 템플릿의 빈 첫 문단이 아니라 **가장 아래** 본문 블록(host)이다.
            let body = try XCTUnwrap(
                page.blocks.filter { $0.kind == .text && $0.role == .body }
                    .max { $0.frame.maxY < $1.frame.maxY }
            )

            // 블록은 CT 높이(3줄 × 16pt)로 커졌고, 이 쪽에 실린 각주의 구분선은 그 아래여야
            // 한다 (자리가 없으면 다음 쪽으로 옮겨지는 것이 옳다).
            expect(body.frame.height).to(beCloseTo(48, within: 1))
            for note in Support.footnoteBlocks(on: page) {
                expect(note.separatorLine.minY) >= body.frame.maxY - 0.01
            }
            expect(Support.footnoteBlocks(on: firstPage).count
                + Support.footnoteBlocks(on: secondPage).count) == 1
        }

        /// 캐시 분할 지점이 뒤에 있어도 **앞 조각 전체**가 들어가야 나눈다 (#165 리뷰).
        /// 첫 줄만 보고 나누면 분할 지점까지의 줄이 전부 방출돼 스택이 자리를 넘고, 바닥
        /// 정렬이 그 스택을 본문 위로 올린다 — 캐시가 저작된 자리보다 우리 본문 하한이
        /// 낮을 때(stale 보정 등) 생긴다. 안 들어가면 통째로 다음 쪽이다.
        func testHeadMustFitWhollyBeforeSplitting() async throws {
            // 분할 지점이 셋째 줄 뒤 — 앞 조각 32.44pt는 15pt 자리에 못 들어간다.
            let note = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            let host = try Support.host(at: Support.hostLocation(leaving: 15), notes: [[note]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))
            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)
            let page = try XCTUnwrap(firstPage)
            let body = try XCTUnwrap(
                page.blocks.filter { $0.kind == .text && $0.role == .body }
                    .max { $0.frame.maxY < $1.frame.maxY }
            )
            for placed in Support.footnoteBlocks(on: page) {
                expect(placed.separatorLine.minY) >= body.frame.maxY - 0.01
            }
            expect(Support.footnoteBlocks(on: firstPage).count
                + Support.footnoteBlocks(on: secondPage).count) >= 1
            expect(Support.text(try XCTUnwrap(Support.footnoteBlocks(on: secondPage).first)))
                .to(contain("첫째 줄"))
        }

        /// 본문 하한은 프레임이 아니라 **그려지는 범위**다 (#165 리뷰). 표 안의 글 앞으로
        /// 개체는 행을 키우지 않고 표 아래로 그려지므로, 프레임만 보면 각주 스택이 그 개체
        /// 위에 놓인다 — 겹침 가드(`FixtureFootnoteOverlapTests`)와 같은 정의를 쓴다.
        func testBodyBottomIncludesPaintedDescendantsBelowTheFrame() async throws {
            // 앞 조각(3줄, 32.44pt)은 개체 아래 자리(≈46pt)에 들어가고, 전체(102.76pt)는
            // 표 프레임 기준 자리(≈216pt)엔 들어가지만 개체 아래엔 안 들어간다.
            let note = try Support.note(
                lines: (1 ... 9).map { "줄 \($0)" },
                locations: [0, 1172, 2344, 0, 1172, 2344, 3516, 4688, 5860]
            )
            let noteHost = try Support.host(at: 40000, notes: [[note]])
            var cell = try HwpSynthetic.textParagraph("셀")
            cell.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.floatingShapeObject(
                width: 20000, height: 20000, textWrap: .inFrontOfText
            ))]
            var tableHost = try HwpSynthetic.lineSegParagraph(
                "", segments: [(location: 48268, height: 1000)]
            )
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 11)]
            tableHost.paraText = paraText
            tableHost.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000, rowHeights: [3000], cellParagraphs: [[[cell]]]
                ),
                treatAsChar: true
            ))]
            let paginator = Support.paginate([noteHost, tableHost] + (try Support.nextPageBody()))
            let firstPage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(firstPage)
            let tableBlock = try XCTUnwrap(page.blocks.first { $0.kind == .table && $0.role == .body })
            guard case let .table(table) = tableBlock.payload else {
                return fail("표 블록의 payload가 없다")
            }
            var paintedBottom = tableBlock.frame.maxY
            HwpBlockContentWalker.walkTable(
                table, origin: tableBlock.frame.origin,
                onParagraphText: { _, _, _ in },
                onCellShape: { shape, rect in
                    paintedBottom = max(paintedBottom, shape.paintedRect.offsetBy(
                        dx: rect.minX - shape.rect.minX, dy: rect.minY - shape.rect.minY
                    ).maxY)
                }
            )
            // 개체가 표 프레임 아래로 그려진다는 전제부터 확인한다.
            expect(paintedBottom) > tableBlock.frame.maxY + 100
            let placed = Support.footnoteBlocks(on: page)
            expect(placed.count) == 1
            for block in placed {
                expect(block.separatorLine.minY) >= paintedBottom - 0.01
            }
        }

        /// 문서 끝 미주 쪽에 이월된 각주가 놓일 때 미주는 본문이다 (#165 리뷰). 미주 블록은
        /// 각주와 같은 `.footnote` 종류라 본문 하한이 그것을 빼면 그 쪽이 빈 쪽으로 보여 각주
        /// 스택이 쪽 전체에 바닥 정렬되고, 진행 보장으로 이미 놓인 미주를 덮는다. 쪽 각주는
        /// 하한을 잰 **뒤에** 붙으므로 그 시점의 `.footnote` 블록은 전부 미주다.
        func testCarriedFootnotesStackBelowDocumentEndEndnotes() async throws {
            // 각주 셋(각 ≈349pt, 분할 지점 없음)은 첫 쪽 15pt 자리에 못 들어가 통째로 이월되고,
            // 둘째 쪽(본문 한 줄)엔 하나만 들어간다. 남은 둘은 미주 쪽에서 예약이 미주 자리를
            // 거의 남기지 않아 미주는 진행 보장으로 쪽 위에 놓이는데, 둘을 합치면 빈 쪽에는
            // 꼭 들어가는 크기라 쪽 전체에 바닥 정렬하면 스택이 미주를 덮는다.
            let notes = try (1 ... 3).map { number in
                try Support.note(
                    lines: (1 ... 30).map { "각주 \(number) 줄 \($0)" },
                    locations: (0 ..< 30).map { Int32($0) * 1172 }
                )
            }
            var host = try HwpSynthetic.splitParagraphWithMixedMarkers(
                lines: [(characters: 5, markers: [17, 17, 17, 17])],
                segments: [(location: Support.hostLocation(leaving: 15), height: 1000, textStart: 0)]
            )
            host.ctrlHeaderArray = notes.map {
                .footnote(HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [$0]))
            } + [.endnote(HwpSynthetic.listControl(
                ctrlId: .endnote,
                paragraphs: [HwpSynthetic.noteParagraph(
                    " 미주 첫 줄\n미주 둘째 줄\n미주 셋째 줄",
                    autoNumber: HwpSynthetic.autoNumberControl(kind: 2, decorationTail: ")")
                )]
            ))]
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))
            var pages: [HwpPage] = []
            var index = 0
            while let page = try await paginator.page(at: index) {
                pages.append(page)
                index += 1
            }
            // 미주 쪽: 미주 블록이 있고 각주 블록이 그 아래에 있어야 한다 — 미주 본문 텍스트로 가른다.
            let endnotePage = try XCTUnwrap(pages.first { page in
                Support.footnoteBlocks(on: page).contains { Support.text($0).contains("미주 첫 줄") }
            })
            let blocks = Support.footnoteBlocks(on: endnotePage)
            let endnotes = blocks.filter { Support.text($0).contains("미주") }
            let footnotes = blocks.filter { !Support.text($0).contains("미주") }
            expect(endnotes.count) == 1
            expect(footnotes.isEmpty) == false
            let endnoteBottom = try XCTUnwrap(endnotes.first).frame.maxY
            for footnote in footnotes {
                expect(footnote.separatorLine.minY) >= endnoteBottom - 0.01
                expect(footnote.frame.minY) >= endnoteBottom - 0.01
            }
            // 세 각주 모두 어딘가에 한 번씩 실린다.
            let allFootnotes = pages.flatMap { Support.footnoteBlocks(on: $0) }
                .filter { !Support.text($0).contains("미주") }
            expect(allFootnotes.count) == 3
        }

        /// 빈 쪽에도 안 들어가 진행 보장으로 실린 거대 각주는 영역 상단이 본문 상단에
        /// 클램프되는데, 위 여백보다 굵은 구분선은 획 반 두께가 그 위로 나간다 (#165 리뷰).
        /// 획까지 본문 상단 아래에 있어야 머리말·위 여백으로 새지 않는다.
        func testThickSeparatorStaysInsideTheClampedArea() throws {
            let shape = try Self.thickDividerShape()
            expect(shape.dividerInfo?.thickness) == 15
            expect(shape.dividerInfo?.marginTop) == 0

            // 70줄(820pt)은 698pt 쪽에 안 들어가고 분할 지점도 없다 — 진행 보장으로 실린다.
            let note = try Support.note(
                lines: (1 ... 70).map { "줄 \($0)" }, locations: (0 ..< 70).map { Int32($0) * 1172 }
            )
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let geometry = Support.geometry(contentWidth: 451)
            let placement = layout.place(
                footnotes: [HwpFootnoteLayout.Input(paragraph: note, number: 1)],
                onPage: geometry, index: HwpIndex(from: CoreHwp.HwpFile()), footnoteShape: shape,
                limitsAreaToHalfContent: false, bodyBottom: geometry.contentFrame.maxY - 15
            )
            let block = try XCTUnwrap(placement.blocks.first)
            expect(block.separatorLine.height).to(beCloseTo(14.17, within: 0.01))
            expect(block.separatorLine.minY) >= geometry.contentFrame.minY - 0.001
            // 첫 줄은 여전히 선 가운데 + 아래 여백 뒤에서 시작한다.
            expect(block.frame.minY).to(beCloseTo(block.separatorLine.midY + 8.5, within: 0.01))
        }

        /// 최상위 도형·그림 블록도 프레임을 넘어 칠한다 (#165 리뷰): 도형은 경로를 프레임
        /// 원점으로 옮겨 클립 없이 긋고(회전 경로·굵은 획), 그림은 테두리를 프레임 경로 중앙에
        /// 그어 절반이 밖이다. 본문 하한이 그 칠을 담아야 각주 스택이 그 위에 놓이지 않는다.
        func testPaintedBoundsIncludeTopLevelShapeAndImagePaint() {
            let frame = CGRect(x: 100, y: 100, width: 50, height: 40)
            // 도형-로컬 경로가 프레임 아래 20pt까지 내려가고 획 6pt가 그 위에 얹힌다.
            let path = CGMutablePath()
            path.addLines(between: [
                CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 25, y: 60),
            ])
            path.closeSubpath()
            let shape = AnyHwpBlock(
                frame: frame, kind: .shape,
                payload: .shape(HwpShapeGeometry(
                    path: path, fillColor: nil, strokeColor: .hwpBlack, strokeWidth: 6
                ))
            )
            let shapeBounds = HwpHitTester.paintedObjectBounds(of: shape)
            expect(shapeBounds.maxY) > frame.maxY + 20
            expect(shapeBounds.contains(frame)) == true

            let image = AnyHwpBlock(
                frame: frame, kind: .image,
                payload: .image(HwpImageBlockInfo(
                    binItemId: 1, borderColor: HwpRGBColor(red: 0, green: 0, blue: 0),
                    borderWidth: 6, style: nil
                ))
            )
            expect(HwpHitTester.paintedObjectBounds(of: image).maxY).to(beCloseTo(frame.maxY + 3, within: 0.001))
            // 텍스트 블록은 프레임 그대로다.
            let text = AnyHwpBlock(frame: frame, kind: .text, attributedString: NSAttributedString(string: "가"))
            expect(HwpHitTester.paintedObjectBounds(of: text)) == frame
        }

        /// 획 반 두께가 위 여백보다 굵은 구분선은 영역 상단의 하한을 그만큼 내린다 — 그 몫을
        /// **자리**에서도 빼야 한다 (#165 리뷰). 빼지 않으면 자리에 꼭 맞게 들어간 스택이
        /// 클램프에 밀려 본문 하단 밖으로 나간다 — 나눠 넘기거나 다음 쪽으로 옮겨야 할 각주다.
        func testSeparatorOverhangCountsAgainstTheAvailableHeight() throws {
            let shape = try Self.thickDividerShape()
            // 30줄(348.88)+29줄(337.16)+사이 여백 2.83 = 688.87 — 획 몫(7.09)을 안 뺀 자리
            // (689.0)엔 들어가고 뺀 자리(682.4)엔 안 들어간다.
            let notes = try [(1, 30), (2, 29)].map { number, lines in
                try Support.note(
                    lines: (1 ... lines).map { "각주 \(number) 줄 \($0)" },
                    locations: (0 ..< lines).map { Int32($0) * 1172 }
                )
            }
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let geometry = Support.geometry(contentWidth: 451)
            let placement = layout.place(
                footnotes: notes.enumerated().map { offset, note in
                    HwpFootnoteLayout.Input(paragraph: note, number: offset + 1)
                },
                onPage: geometry, index: HwpIndex(from: CoreHwp.HwpFile()), footnoteShape: shape,
                limitsAreaToHalfContent: false, bodyBottom: geometry.contentFrame.minY + 0.5
            )
            // 둘째 각주는 다음 쪽이고, 실린 스택은 본문 하단 안에 있다.
            expect(placement.blocks.count) == 1
            expect(placement.overflow.count) == 1
            let block = try XCTUnwrap(placement.blocks.first)
            expect(block.frame.maxY) <= geometry.contentFrame.maxY + 0.01
            expect(block.separatorLine.minY) >= geometry.contentFrame.minY - 0.001
        }

        /// 위 여백 0·아래 여백 850·굵기 index 15 (5mm = 14.17pt) 인 구분선 모양 —
        /// `dividerInfo`는 rawPayload를 다시 디코딩하므로 28바이트를 직접 조립한다.
        static func thickDividerShape() throws -> CoreHwp.HwpFootnoteShape {
            var shape = CoreHwp.HwpFootnoteShape(
                dividerLength: 0, dividerMarginTop: 0, dividerType: 0, dividerThickness: 15
            )
            var payload = Data(count: 12)
            withUnsafeBytes(of: Int32(0).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int16(0).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int16(850).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int16(283).littleEndian) { payload.append(contentsOf: $0) }
            payload.append(contentsOf: [0, 15])
            withUnsafeBytes(of: UInt32(0).littleEndian) { payload.append(contentsOf: $0) }
            shape.rawPayload = payload
            return shape
        }
    }
#endif

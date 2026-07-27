import CoreGraphics
import Foundation
@testable import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 실제 fixture 문서로 표/글상자/각주/그림 렌더 파이프라인을 검증하는 통합 테스트.
final class FixtureObjectRenderTests: XCTestCase {
    // MARK: - noori (표 + 그림 + 본문 텍스트)

    func testNooriRendersTableWithRowsAndCellText() async throws {
        let document = try await loadFixture("noori")

        let tables = allBlocks(in: document).filter { $0.kind == .table }
        expect(tables.count) >= 1

        let richTable = tables.compactMap { block -> HwpTableFrame? in
            guard case let .table(frame) = block.payload else { return nil }
            return frame
        }.first { frame in
            frame.rows.count >= 2 && frame.rows.contains { row in
                row.cells.contains { cell in
                    cell.paragraphs.contains { !$0.attributedString.string.isEmpty }
                }
            }
        }
        expect(richTable).toNot(beNil(), description: "noori 표에 2행 이상 + 셀 텍스트가 있어야 한다")
    }

    func testNooriPaintListContainsImageReference() async throws {
        let document = try await loadFixture("noori")
        let references = imageReferenceIds(in: document)
        expect(references.count) >= 1
    }

    func testNooriStillRendersBodyText() async throws {
        let document = try await loadFixture("noori")
        let rendered = FixtureText.extract(from: document)
        expect(rendered).to(contain("한국형발사체"))
    }

    func testNooriInlineImageAnchorsToItsLine() async throws {
        let document = try await loadFixture("noori")
        guard let page = document.pages.first else {
            fail("첫 페이지가 없다")
            return
        }
        // 첫 문단은 구역/단/gso 컨트롤 문자 3개 (U+FFFC×3)만 가진다.
        guard let host = page.blocks.first(where: { $0.kind == .text }) else {
            fail("첫 텍스트 블록이 없다")
            return
        }
        let markers = (host.attributedString?.string ?? "").filter { $0 == "\u{FFFC}" }
        expect(markers.count) == 3

        guard let image = page.blocks.first(where: { block in
            guard block.kind == .image, case let .image(info) = block.payload else { return false }
            return info.binItemId == 1
        }) else {
            fail("binItemId 1 인라인 이미지 블록이 없다")
            return
        }
        // treatAsChar 이미지는 문단 뒤 흐름 위치가 아니라 FFFC가 있는 줄에 배치된다.
        expect(image.frame.minY).to(
            beCloseTo(host.frame.minY, within: 2),
            description: "인라인 이미지 y가 FFFC 줄의 y와 일치해야 한다"
        )
        expect(image.frame.minY) < host.frame.maxY
    }

    // MARK: - BinData (그림 3장)

    func testBinDataRendersThreeDistinctImageReferences() async throws {
        let document = try await loadFixture("BinData")

        let storedIds = Set(document.imageStore.dataByBinItemId.keys)
        expect(storedIds.isSuperset(of: [1, 2, 3])) == true

        let referencedIds = imageReferenceIds(in: document)
        expect(referencedIds) == Set<UInt32>([1, 2, 3])
    }

    // MARK: - text-box (글상자)

    func testTextBoxRendersTextboxBlockWithParagraphText() async throws {
        let document = try await loadFixture("text-box")

        let textboxFrames = allBlocks(in: document).compactMap { block -> HwpTextboxFrame? in
            guard block.kind == .textbox, case let .textbox(frame) = block.payload
            else { return nil }
            return frame
        }
        expect(textboxFrames.count) >= 1

        let allText = textboxFrames
            .flatMap(\.paragraphs)
            .map(\.attributedString.string)
            .joined(separator: "\n")
        let containsExpected = allText.contains("inside box")
            || allText.contains("Text box fixture")
        expect(containsExpected).to(
            beTrue(),
            description: "글상자 문단 텍스트가 비어 있음 — got: '\(allText.prefix(120))'"
        )
    }

    func testTextBoxPaintListContainsBoxRect() async throws {
        let document = try await loadFixture("text-box")

        let hasBoxRect = document.pages.contains { page in
            guard page.blocks.contains(where: { $0.kind == .textbox }) else { return false }
            return page.paintList.commands.contains { command in
                if case .strokeRect = command {
                    return true
                }
                if case .fillRect = command {
                    return true
                }
                return false
            }
        }
        expect(hasBoxRect) == true
    }

    // MARK: - footnote-endnote (각주/미주)

    func testFootnoteEndnoteRendersFootnoteBlockWithSeparator() async throws {
        let document = try await loadFixture("footnote-endnote")

        var found = false
        for page in document.pages {
            let footnotes = page.blocks.compactMap { block -> HwpFootnoteBlock? in
                guard block.kind == .footnote, case let .footnote(footnote) = block.payload
                else { return nil }
                return footnote
            }
            guard let footnote = footnotes.first else { continue }
            expect(footnote.number) >= 1
            let hasSeparator = page.paintList.commands.contains { command in
                if case let .fillRect(rect, _) = command {
                    return rect == footnote.separatorLine
                }
                return false
            }
            expect(hasSeparator).to(beTrue(), description: "각주 구분선 fillRect가 있어야 한다")
            found = true
            break
        }
        expect(found).to(beTrue(), description: "각주 블록 (payload 포함)이 있어야 한다")
    }

    func testFootnoteEndnoteSeparateNumberingAndEndnoteOnLastPage() async throws {
        let document = try await loadFixture("footnote-endnote")
        guard let lastPage = document.pages.last else {
            fail("페이지가 없다")
            return
        }

        var footnoteNumber: Int?
        var endnoteNumber: Int?
        var endnoteOnLastPage = false
        for page in document.pages {
            for block in page.blocks where block.kind == .footnote {
                guard case let .footnote(note) = block.payload else { continue }
                let text = note.paragraphs.first?.attributedString.string ?? ""
                if text.contains("footnote fixture") {
                    footnoteNumber = note.number
                }
                if text.contains("endnote fixture") {
                    endnoteNumber = note.number
                    endnoteOnLastPage = page.pageNumber == lastPage.pageNumber
                }
            }
        }
        // 각주/미주는 별도 카운터: 둘 다 시작 번호 1이다.
        expect(footnoteNumber) == 1
        expect(endnoteNumber) == 1
        expect(endnoteOnLastPage).to(beTrue(), description: "미주가 마지막 페이지에 있어야 한다")
    }

    // MARK: - header-footer (머리말/꼬리말 페이지 반복)

    func testHeaderFooterRendersBandsOnEveryPage() async throws {
        let document = try await loadFixture("header-footer")
        expect(document.pages.count) >= 1

        for (pageIndex, page) in document.pages.enumerated() {
            let paintText = page.paintList.commands.compactMap { command -> String? in
                if case let .drawText(attributed, _, _) = command {
                    return attributed.string
                }
                return nil
            }.joined(separator: "\n")
            expect(paintText).to(
                contain("CoreHwp header fixture"),
                description: "page \(pageIndex + 1) paint list에 머리말이 없다"
            )
            expect(paintText).to(
                contain("CoreHwp footer fixture"),
                description: "page \(pageIndex + 1) paint list에 꼬리말이 없다"
            )
        }
    }

    // MARK: - Column (다단)

    func testColumnFixtureRendersMultiColumnTextWithinBounds() async throws {
        let document = try await loadFixture("Column")
        expect(document.pages.count) >= 1

        var bodyOrigins = Set<CGFloat>()
        for page in document.pages {
            let contentMinX = page.margins.left
            let contentMaxX = page.size.width - page.margins.right
            for block in page.blocks where block.kind == .text {
                // 컨트롤 문자(U+FFFC)뿐인 블록은 본문 텍스트가 아니다.
                let visible = (block.attributedString?.string ?? "")
                    .filter { $0 != "\u{FFFC}" && !$0.isWhitespace }
                guard !visible.isEmpty else { continue }
                bodyOrigins.insert(block.frame.minX)
                expect(block.frame.minX).to(
                    beGreaterThanOrEqualTo(contentMinX - 0.5),
                    description: "본문 블록이 왼쪽 여백을 침범한다"
                )
                expect(block.frame.maxX).to(
                    beLessThanOrEqualTo(contentMaxX + 0.5),
                    description: "본문 블록이 오른쪽 여백을 침범한다"
                )
            }
        }
        // 2단/3단 구간이 있으므로 서로 다른 x-origin 텍스트 블록이 존재해야 한다.
        expect(bodyOrigins.count) >= 2
    }

    // MARK: - chart (미지원 OLE/차트)

    func testChartReportsUnsupportedPlaceholder() async throws {
        let document = try await loadFixture("chart")
        expect(document.pages.count) >= 1
        // 차트는 genShapeObject 안 chartData record로 들어오며,
        // detector가 개체 요소 단위 검사로 placeholder를 보고한다.
        let hints = document.unsupportedElements.map(\.hint)
        let mentionsChart = hints.contains { $0.contains("차트") || $0.contains("OLE") }
        expect(mentionsChart).to(
            beTrue(),
            description: "unsupported hints: \(hints)"
        )
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) async throws -> HwpDocument {
        let url = FixtureRoot.url(from: #file)
            .appendingPathComponent(name)
            .appendingPathComponent("document.hwp")
        return try await HwpDocumentLoader().load(from: url)
    }

    private func allBlocks(in document: HwpDocument) -> [AnyHwpBlock] {
        document.pages.flatMap(\.blocks)
    }

    private func imageReferenceIds(in document: HwpDocument) -> Set<UInt32> {
        var ids = Set<UInt32>()
        for page in document.pages {
            for command in page.paintList.commands {
                if case let .drawImageReference(binItemId, _, _, _) = command {
                    ids.insert(binItemId)
                }
            }
        }
        return ids
    }
}

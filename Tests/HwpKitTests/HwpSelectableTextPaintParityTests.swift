import CoreGraphics
import CoreHwp
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// 선택↔렌더 패리티 불변 테스트 — "미러 드리프트" 버그 클래스의 CI 가드.
///
/// `HwpSelectableText.units(in:)`의 (문자열, origin, 폭) 시퀀스는
/// `HwpPaintListBuilder`가 role == .body 블록에서 방출하는 `.drawText`
/// (attributedString, origin, lineWidth) 시퀀스와 완전히 같아야 한다.
/// 한쪽 방출 규칙(표 셀/중첩 표/글상자/각주의 offset·순서)만 바뀌면
/// 선택 하이라이트가 렌더와 어긋난다 — 이 테스트가 그 드리프트를 잡는다.
final class HwpSelectableTextPaintParityTests: XCTestCase {
    // MARK: - 실픽스처 전 페이지 루프

    func testFixturePagesHaveSelectionPaintParity() async throws {
        // 표 분할·셀 그림·다단 (noori), 각주 이월·미주 (footnote-endnote),
        // 구역 전환 (multi-section)
        for fixture in ["noori", "footnote-endnote", "multi-section"] {
            let documentURL = FixtureRoot.url(from: #file)
                .appendingPathComponent(fixture)
                .appendingPathComponent("document.hwp")
            let document = try await HwpDocumentLoader().load(from: documentURL)

            var totalUnits = 0
            for (pageIndex, page) in document.pages.enumerated() {
                let failures = Self.parityFailures(
                    in: page,
                    context: "[\(fixture)] p\(pageIndex)"
                )
                if !failures.isEmpty {
                    fail(failures.joined(separator: "\n"))
                }
                totalUnits += HwpSelectableText.units(in: page).count
            }
            // 공허한 통과 방지 — 픽스처마다 실제 선택 단위가 있어야 한다
            expect(totalUnits).to(
                beGreaterThan(0),
                description: "[\(fixture)] 선택 단위가 하나도 없다 — 대조가 공허하다"
            )
        }
    }

    // MARK: - 합성 복합 페이지 (중첩 표 + 글상자 + 각주 + 빈 문단 + 크롬)

    func testSyntheticComplexPageHasSelectionPaintParity() {
        let page = Self.makeSyntheticComplexPage()

        let failures = Self.parityFailures(in: page, context: "[synthetic]")
        if !failures.isEmpty {
            fail(failures.joined(separator: "\n"))
        }

        // 기대 구성 확인: 본문 1 + 바깥 셀 문단 2 + 중첩 셀 문단 1 +
        // 글상자 문단 2 + 각주 문단 1 + 각주 글상자 1 + 각주 표 셀 1 = 9
        // (빈 문단·크롬·둘째 셀 빈 텍스트 제외). 각주 개체 텍스트가 순서대로
        // 각주 문단 뒤에 오는 것이 렌더 방출 순서와 같은 규약이다 (#94).
        let units = HwpSelectableText.units(in: page)
        expect(units.map(\.attributedString.string)) == [
            "본문 문단",
            "셀 문단 하나",
            "셀 문단 둘",
            "중첩 셀",
            "글상자 첫 문단",
            "글상자 둘째 문단",
            "1) 각주 본문",
            "각주 글상자",
            "각주 표 셀",
        ]
    }

    // MARK: - 패리티 대조 헬퍼

    /// (문자열, origin, 폭) 방출 하나 — 선택 단위와 drawText 명령의 공통 투영.
    private struct TextEmission: Equatable, CustomStringConvertible {
        let string: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat

        var description: String {
            let prefix = string.prefix(12)
            return "'\(prefix)' @(\(x), \(y)) w=\(width)"
        }
    }

    private static func parityFailures(in page: HwpPage, context: String) -> [String] {
        let selection = selectionEmissions(in: page)
        let paint = bodyDrawTextEmissions(in: page)

        var failures: [String] = []
        if selection.count != paint.count {
            failures.append(
                "\(context) 개수 불일치: 선택 \(selection.count) != drawText \(paint.count)"
            )
        }
        for (index, pair) in zip(selection, paint).enumerated() where pair.0 != pair.1 {
            failures.append(
                "\(context) #\(index): 선택 \(pair.0) != drawText \(pair.1)"
            )
            if failures.count > 10 {
                failures.append("\(context) … (이후 생략)")
                break
            }
        }
        return failures
    }

    private static func selectionEmissions(in page: HwpPage) -> [TextEmission] {
        HwpSelectableText.units(in: page).map { unit in
            TextEmission(
                string: unit.attributedString.string,
                x: unit.rect.minX,
                y: unit.rect.minY,
                // drawText lineWidth는 max(폭, 1)로 클램프된다 — 같은 투영으로 대조
                width: max(unit.rect.width, 1)
            )
        }
    }

    /// role == .body 블록이 방출하는 `.drawText`만 뽑는다.
    ///
    /// `HwpPaintListBuilder.build`는 페이지 전체 (크롬 포함)를 방출하고 블록
    /// 단위 공개 API가 없으므로, 블록 하나짜리 페이지 사본을 build해 명령을
    /// 블록별로 귀속시킨다 (명령 생성은 블록별 독립 — 각주 구분선 공유 로직은
    /// fillRect에만 영향). 차트 블록은 제외한다: 차트 라벨 drawText는 합성
    /// 렌더 근사일 뿐 문서 텍스트가 아니라 선택 대상에서 설계상 빠진다
    /// (HwpSelectableText와 같은 계약).
    private static func bodyDrawTextEmissions(in page: HwpPage) -> [TextEmission] {
        let builder = HwpPaintListBuilder()
        var emissions: [TextEmission] = []
        for block in page.blocks where block.role == .body {
            if case .chart = block.payload {
                continue
            }
            let singleBlockPage = HwpPage(
                size: page.size,
                margins: page.margins,
                blocks: [block],
                pageNumber: page.pageNumber
            )
            for command in builder.build(for: singleBlockPage).commands {
                if case let .drawText(attributed, origin, lineWidth) = command {
                    emissions.append(TextEmission(
                        string: attributed.string,
                        x: origin.x,
                        y: origin.y,
                        width: lineWidth
                    ))
                }
            }
        }
        return emissions
    }

    // MARK: - 합성 페이지 구성

    private static func makeSyntheticComplexPage() -> HwpPage {
        let footnoteFrame = CGRect(x: 72, y: 700, width: 400, height: 40)
        let blocks = [
            AnyHwpBlock(
                frame: CGRect(x: 72, y: 72, width: 400, height: 20),
                kind: .text,
                attributedString: NSAttributedString(string: "본문 문단")
            ),
            AnyHwpBlock(
                frame: CGRect(x: 72, y: 110, width: 300, height: 120),
                kind: .table,
                payload: .table(makeOuterTable())
            ),
            AnyHwpBlock(
                frame: CGRect(x: 90, y: 260, width: 200, height: 80),
                kind: .textbox,
                payload: .textbox(makeTextbox())
            ),
            AnyHwpBlock(
                frame: footnoteFrame,
                kind: .footnote,
                payload: .footnote(makeFootnote(frame: footnoteFrame))
            ),
            // 크롬은 선택에서 제외 — 패리티 대조 양쪽 모두 body만 본다
            AnyHwpBlock(
                frame: CGRect(x: 72, y: 800, width: 400, height: 20),
                kind: .text,
                attributedString: NSAttributedString(string: "- 1 -"),
                role: .pageChrome
            ),
        ]
        return HwpPage(
            size: CGSize(width: 595, height: 842),
            margins: HwpPageMargins(top: 72, left: 72, bottom: 72, right: 72),
            blocks: blocks,
            pageNumber: 1
        )
    }

    private static func makeTextbox() -> HwpTextboxFrame {
        HwpTextboxFrame(
            outerFrame: CGRect(x: 0, y: 0, width: 200, height: 80),
            paragraphs: [
                paragraph(
                    "글상자 첫 문단",
                    rect: CGRect(x: 6, y: 6, width: 188, height: 20)
                ),
                paragraph(
                    "글상자 둘째 문단",
                    rect: CGRect(x: 6, y: 30, width: 188, height: 20)
                ),
            ],
            borderColor: HwpRGBColor(red: 0, green: 0, blue: 0),
            borderWidth: 1,
            fillColor: nil
        )
    }

    /// 각주: 문단 1 + 각주 안 그림 + 각주 안 글상자 + 각주 안 표 (#94).
    /// 각주 개체 방출이 늘어도 선택 단위와 drawText 순서가 어긋나지 않아야
    /// 한다 — 각주는 표 셀·글상자와 같은 컨테이너 규약을 따른다.
    private static func makeFootnote(frame: CGRect) -> HwpFootnoteBlock {
        HwpFootnoteBlock(
            frame: frame,
            paragraphs: [paragraph(
                "1) 각주 본문",
                rect: CGRect(x: 0, y: 8, width: 400, height: 20)
            )],
            number: 1,
            separatorLine: CGRect(x: 72, y: 696, width: 150, height: 1),
            images: [HwpCellImage(
                rect: CGRect(x: 300, y: 8, width: 12, height: 12),
                binItemId: 3,
                style: nil,
                controlInstanceId: 21
            )],
            textboxes: [HwpCellTextbox(
                rect: CGRect(x: 200, y: 8, width: 90, height: 20),
                textbox: HwpTextboxFrame(
                    outerFrame: CGRect(x: 0, y: 0, width: 90, height: 20),
                    paragraphs: [paragraph(
                        "각주 글상자",
                        rect: CGRect(x: 2, y: 2, width: 86, height: 16)
                    )],
                    borderColor: nil,
                    borderWidth: 0,
                    fillColor: nil
                ),
                paintsBehindText: false,
                zOrder: 0,
                sourceOrder: 1,
                controlInstanceId: 22
            )],
            nestedTables: [HwpNestedTableFrame(
                rect: CGRect(x: 0, y: 30, width: 80, height: 20),
                table: makeNestedTable(text: "각주 표 셀"),
                controlInstanceId: 23,
                // 표도 개체와 같은 정렬 키를 쓰므로 (R47 #1) 글상자(1) 뒤에
                // 선언된 순서를 명시한다 — 기본 0이면 글상자보다 앞서 정렬된다.
                sourceOrder: 2
            )]
        )
    }

    /// 바깥 표: 1행 2셀 — 첫 셀은 문단 2 + 그림 + 중첩 표 인터리빙,
    /// 둘째 셀은 빈 문단 (양쪽 다 제외돼야 한다)
    private static func makeOuterTable() -> HwpTableFrame {
        let tableRect = CGRect(x: 0, y: 0, width: 300, height: 120)
        return HwpTableFrame(
            outerFrame: tableRect,
            rows: [HwpTableRowFrame(
                rowFrame: tableRect,
                cells: [makeFirstCell(), makeSecondCell()]
            )],
            borderColor: HwpRGBColor(red: 0, green: 0, blue: 0),
            borderWidth: 1
        )
    }

    /// 첫 셀: 문단 2 + 셀 그림 + 중첩 표 인터리빙
    private static func makeFirstCell() -> HwpTableCellFrame {
        HwpTableCellFrame(
            cellFrame: CGRect(x: 0, y: 0, width: 150, height: 120),
            row: 0,
            column: 0,
            rowSpan: 1,
            columnSpan: 1,
            paragraphs: [
                paragraph(
                    "셀 문단 하나",
                    rect: CGRect(x: 4, y: 4, width: 140, height: 20)
                ),
                paragraph(
                    "셀 문단 둘",
                    rect: CGRect(x: 4, y: 26, width: 140, height: 20)
                ),
            ],
            borders: .uniform(width: 0.5, color: HwpRGBColor(red: 0, green: 0, blue: 0)),
            fillColor: HwpRGBColor(red: 1, green: 1, blue: 0.8),
            nestedTables: [HwpNestedTableFrame(
                rect: CGRect(x: 8, y: 80, width: 80, height: 30),
                table: makeNestedTable(),
                controlInstanceId: 11
            )],
            images: [HwpCellImage(
                rect: CGRect(x: 100, y: 50, width: 40, height: 20),
                binItemId: 1,
                style: nil,
                controlInstanceId: 12
            )]
        )
    }

    /// 둘째 셀: 빈 문단 (선택·drawText 양쪽 다 제외돼야 한다)
    private static func makeSecondCell() -> HwpTableCellFrame {
        HwpTableCellFrame(
            cellFrame: CGRect(x: 150, y: 0, width: 150, height: 120),
            row: 0,
            column: 1,
            rowSpan: 1,
            columnSpan: 1,
            paragraphs: [paragraph(
                "",
                rect: CGRect(x: 154, y: 4, width: 140, height: 20)
            )],
            borders: .uniform(width: 0.5, color: HwpRGBColor(red: 0, green: 0, blue: 0)),
            fillColor: nil
        )
    }

    /// 중첩 표: 셀 하나 + 문단 하나
    private static func makeNestedTable(text: String = "중첩 셀") -> HwpTableFrame {
        let black = HwpRGBColor(red: 0, green: 0, blue: 0)
        let nestedRect = CGRect(x: 0, y: 0, width: 80, height: 30)
        return HwpTableFrame(
            outerFrame: nestedRect,
            rows: [HwpTableRowFrame(rowFrame: nestedRect, cells: [
                HwpTableCellFrame(
                    cellFrame: nestedRect,
                    row: 0,
                    column: 0,
                    rowSpan: 1,
                    columnSpan: 1,
                    paragraphs: [paragraph(
                        text,
                        rect: CGRect(x: 4, y: 4, width: 72, height: 20)
                    )],
                    borders: .uniform(width: 0.5, color: black),
                    fillColor: nil
                ),
            ])],
            borderColor: black,
            borderWidth: 1
        )
    }

    private static func paragraph(_ text: String, rect: CGRect) -> HwpLaidOutParagraph {
        HwpLaidOutParagraph(
            attributedString: NSAttributedString(string: text),
            frame: HwpParagraphFrame(totalHeight: rect.height, lines: []),
            rect: rect,
            paragraphId: 0
        )
    }
}

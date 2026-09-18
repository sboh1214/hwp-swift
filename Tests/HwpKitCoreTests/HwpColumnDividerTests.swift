@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 단 구분선 (#191) — 단 정의의 선 종류·굵기·색으로 단 사이 간격의 가운데에 밴드 높이만큼
    /// 세로선을 낸다 (한글 12.30.0 실측: x = 간격 중앙, 밴드 첫 줄 위 ~ 가장 긴 단의 마지막
    /// 줄 아래, 둘째 단이 비어도 그린다).
    final class HwpColumnDividerTests: XCTestCase {
        static func column(divider type: UInt8, thickness: UInt8 = 1) -> CoreHwp.HwpColumn {
            var column = HwpSynthetic.column(count: 2, spacing: 1000)
            column.dividerType = type
            column.dividerThickness = thickness
            column.dividerColor = CoreHwp.HwpColor(255, 0, 0)
            return column
        }

        static func page(
            column: CoreHwp.HwpColumn, text: String
        ) async throws -> HwpPage? {
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(column),
                ],
                bodyParagraphs: [try HwpSynthetic.textParagraph(text)]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            return try await paginator.page(at: 0)
        }

        static func dividers(in page: HwpPage) -> [AnyHwpBlock] {
            page.blocks.filter { $0.kind == .shape && $0.role == .pageChrome }
        }

        func testDividerSpansTheBandBetweenTheColumns() async throws {
            let maybePage = try await Self.page(
                column: Self.column(divider: 4), // 일점쇄선
                text: String(repeating: "가나다라 ", count: 40)
            )
            let page = try XCTUnwrap(maybePage)
            let dividers = Self.dividers(in: page)
            expect(dividers.count) == 1
            guard let divider = dividers.first else { return }
            let texts = page.blocks.filter { $0.kind == .text }
            expect(texts.count) >= 2
            let left = try XCTUnwrap(texts.min { $0.frame.minX < $1.frame.minX })
            let right = try XCTUnwrap(texts.max { $0.frame.minX < $1.frame.minX })
            // x: 두 단 사이 간격의 가운데, 폭은 선 굵기 (0.12mm)
            let gapCenter = (left.frame.maxX + right.frame.minX) / 2
            expect(divider.frame.midX).to(beCloseTo(gapCenter, within: 0.01))
            expect(divider.frame.width).to(beCloseTo(0.12 * 72 / 25.4, within: 0.001))
            // y: 밴드 위(첫 줄 위)에서 가장 긴 단의 마지막 줄 글상자 아래(블록 아래에서 줄
            // 간격을 뺀 자리 — 줄 캐시 없는 문단은 마지막 글자의 줄 간격 규칙으로 잰다)까지
            let top = texts.map(\.frame.minY).min() ?? 0
            let bottom = texts.map(\.frame.maxY).max() ?? 0
            let lastText = try XCTUnwrap(texts.max { $0.frame.maxY < $1.frame.maxY })
            let spacing = HwpColumnBandController.measuredTrailingSpacing(
                of: try XCTUnwrap(lastText.attributedString)
            )
            // 빈 문서 기본 문단 모양 10pt·160% → 마지막 줄 줄 간격 6pt
            expect(spacing).to(beCloseTo(6, within: 0.01))
            expect(divider.frame.minY).to(beCloseTo(top, within: 0.01))
            expect(divider.frame.maxY).to(beCloseTo(bottom - spacing, within: 0.01))
            // 경로는 일점쇄선 조각들이고 색은 단 정의의 구분선 색
            guard case let .shape(geometry)? = divider.payload else {
                fail("구분선은 채우기 경로 블록이어야 한다")
                return
            }
            expect(geometry.fillColor?.components?.first).to(beCloseTo(1, within: 0.01))
            expect(geometry.strokeColor).to(beNil())
            let pieces = HwpLineShapeGeometryTests.pieces(geometry.path)
            expect(pieces.count) > 4
            // 첫 조각은 10단위 선, 둘째는 1단위 점 (단위 = 22/15 × 굵기)
            let unit = 0.12 * 72 / 25.4 * 22 / 15
            expect(pieces[0].height).to(beCloseTo(unit * 10, within: 0.001))
            expect(pieces[1].height).to(beCloseTo(unit, within: 0.001))
            expect(pieces[1].minY - pieces[0].maxY).to(beCloseTo(unit * 3, within: 0.001))
            // 페인트 목록에도 채우기 경로로 나간다
            let painted = page.paintList.commands.contains {
                if case let .drawPath(_, fill, _, _) = $0 {
                    return fill != nil
                }
                return false
            }
            expect(painted) == true
        }

        func testDividerIsDrawnEvenWhenTheSecondColumnIsEmpty() async throws {
            let maybePage = try await Self.page(column: Self.column(divider: 1), text: "짧은 문단")
            let page = try XCTUnwrap(maybePage)
            let dividers = Self.dividers(in: page)
            expect(dividers.count) == 1
            let text = try XCTUnwrap(page.blocks.first { $0.kind == .text })
            let spacing = HwpColumnBandController.measuredTrailingSpacing(
                of: try XCTUnwrap(text.attributedString)
            )
            expect(dividers.first?.frame.minY).to(beCloseTo(text.frame.minY, within: 0.01))
            expect(dividers.first?.frame.maxY)
                .to(beCloseTo(text.frame.maxY - spacing, within: 0.01))
        }

        /// 구분선 바닥 규칙 — 밴드 바닥에 본문 줄이 닿았으면 **그 블록**의 마지막 줄 줄 간격
        /// (조판 문자열의 마지막 글자에서 잰다 — 저장 상태가 아니라서 쪽에 걸친 문단·다른 단의
        /// 뒤 문단에 흔들리지 않는다)을 빼고, 표처럼 줄 간격 없는 블록이 바닥이면 사용량
        /// 그대로다 (한글 실측: 표 아래 여백까지). 밴드 바닥까지 내려온 글 앞뒤 개체는 판정을
        /// 바꾸지 않는다. 단 프레임이 오른쪽부터여도 x는 간격 중앙이다.
        func testDividerBottomSubtractsLineSpacingOnlyBelowBodyText() throws {
            var band = HwpColumnBandController()
            band.currentColumnDef = Self.column(divider: 1)
            let leftFrame = CGRect(x: 50, y: 100, width: 200, height: 500)
            let rightFrame = CGRect(x: 300, y: 100, width: 150, height: 500)
            band.columnFrames = [rightFrame, leftFrame] // 오른쪽부터 채우는 단 순서
            band.bandUsedBottom = 300
            func text(size: Double, percent: Double) -> NSAttributedString {
                NSAttributedString(string: "가", attributes: [
                    HwpAttributedStringKey.baseFontSize: NSNumber(value: size),
                    HwpAttributedStringKey.lineSpacing:
                        HwpLineSpacingRule(kind: .percent, value: percent).attributeValue,
                ])
            }
            func block(
                _ kind: HwpBlockKind, role: HwpBlockRole = .body, height: CGFloat = 200,
                text attributed: NSAttributedString? = nil
            ) -> AnyHwpBlock {
                AnyHwpBlock(
                    frame: CGRect(x: 50, y: 100, width: 200, height: height), kind: kind,
                    attributedString: attributed, role: role
                )
            }
            let body = block(.text, text: text(size: 10, percent: 160)) // 줄 간격 6
            let belowText = try XCTUnwrap(band.columnDividerBlocks(currentBlocks: [body]).first)
            expect(belowText.frame.midX).to(beCloseTo(275, within: 0.001))
            expect(belowText.frame.minY).to(beCloseTo(100, within: 0.001))
            expect(belowText.frame.maxY).to(beCloseTo(294, within: 0.001))
            let belowTable = try XCTUnwrap(
                band.columnDividerBlocks(currentBlocks: [block(.table)]).first
            )
            expect(belowTable.frame.maxY).to(beCloseTo(300, within: 0.001))
            // 본문 줄과 함께 바닥에 닿은 글 앞으로 개체는 무시한다
            let withOverlay = try XCTUnwrap(band.columnDividerBlocks(
                currentBlocks: [body, block(.shape)]
            ).first)
            expect(withOverlay.frame.maxY).to(beCloseTo(294, within: 0.001))
            // 쪽 장식 역할의 텍스트(머리말)는 본문이 아니다
            let chromeOnly = try XCTUnwrap(band.columnDividerBlocks(
                currentBlocks: [block(.text, role: .pageChrome, text: text(size: 10, percent: 160))]
            ).first)
            expect(chromeOnly.frame.maxY).to(beCloseTo(300, within: 0.001))
            // 바닥에 닿은 블록의 값이다 — 다른 단의 짧은 뒤 문단(40pt·200% = 40)은 무관
            let other = block(.text, height: 100, text: text(size: 40, percent: 200))
            let twoColumns = try XCTUnwrap(band.columnDividerBlocks(
                currentBlocks: [body, other]
            ).first)
            expect(twoColumns.frame.maxY).to(beCloseTo(294, within: 0.001))
        }

        /// 구분선 바닥은 본문 텍스트 블록마다 (아래 − 그 블록 줄 간격) 중 가장 낮은 자리다 — 298에서
        /// 끝나는 100% 문단의 글상자(298)가 300에서 끝나는 160% 문단의 글상자(294)보다 낮다.
        /// 줄 간격 출처는 호출자가 준다(페이지네이터는 줄 캐시 값).
        func testDividerBottomTakesTheLowestLineBoxAcrossColumns() throws {
            var band = HwpColumnBandController()
            band.currentColumnDef = Self.column(divider: 1)
            band.columnFrames = [
                CGRect(x: 50, y: 100, width: 200, height: 500),
                CGRect(x: 300, y: 100, width: 150, height: 500),
            ]
            band.bandUsedBottom = 300
            func text(percent: Double) -> NSAttributedString {
                NSAttributedString(string: "가", attributes: [
                    HwpAttributedStringKey.baseFontSize: NSNumber(value: 10),
                    HwpAttributedStringKey.lineSpacing:
                        HwpLineSpacingRule(kind: .percent, value: percent).attributeValue,
                ])
            }
            let body = AnyHwpBlock(
                frame: CGRect(x: 50, y: 100, width: 200, height: 200), kind: .text,
                attributedString: text(percent: 160)
            )
            let tight = AnyHwpBlock(
                frame: CGRect(x: 300, y: 100, width: 150, height: 198), kind: .text,
                attributedString: text(percent: 100)
            )
            let nearTie = try XCTUnwrap(
                band.columnDividerBlocks(currentBlocks: [body, tight]).first
            )
            expect(nearTie.frame.maxY).to(beCloseTo(298, within: 0.001))
            let cached = try XCTUnwrap(band.columnDividerBlocks(
                currentBlocks: [body], trailingSpacing: { _ in 12 }
            ).first)
            expect(cached.frame.maxY).to(beCloseTo(288, within: 0.001))
        }

        /// 줄 캐시가 있는 문단은 한글이 저장한 마지막 줄 줄 간격(캐시)을 뺀다 — 문단 모양의 규칙값
        /// (10pt·160% → 6pt)과 다른 12pt 캐시 두 줄로 구분한다 (줄 상자 아래 = 블록 아래 − 12)
        func testDividerBottomUsesTheLineCacheSpacingWhenPresent() async throws {
            var paragraph = try HwpSynthetic.textParagraph("캐시 문단 두 줄")
            var payload = Data()
            // 표 40: textIndex, lineLocation, lineHeight, textHeight, baseline, lineSpacing,
            // colOffset, width, flags
            for line: [UInt32] in [
                [0, 0, 1000, 1000, 850, 1200, 0, 42520, 393_216],
                [5, 2200, 1000, 1000, 850, 1200, 0, 42520, 393_216],
            ] {
                for value in line {
                    withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
                }
            }
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(Self.column(divider: 1)),
                ],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let maybePage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(maybePage)
            let divider = try XCTUnwrap(Self.dividers(in: page).first)
            let text = try XCTUnwrap(
                page.blocks.first { $0.attributedString?.string == "캐시 문단 두 줄" }
            )
            expect(text.frame.height).to(beCloseTo(44, within: 0.01)) // 캐시 (10 + 12) × 2
            expect(HwpColumnBandController.cachedTrailingSpacing(of: paragraph))
                .to(beCloseTo(12, within: 0.001))
            expect(divider.frame.maxY).to(beCloseTo(text.frame.maxY - 12, within: 0.01))
        }

        /// 다음 단·쪽으로 이어지는 조각은 문단 마지막 줄을 담지 않으므로 캐시 값이 아니라 조각
        /// 마지막 글자의 규칙값(6pt)을 뺀다 — 다섯 줄(줄 간격 12×4·30pt) 캐시 문단이 두 단 밴드
        /// (본문 65pt)에 앞 빈 문단 + 2줄 / 2줄로 흐르고 마지막 줄만 2쪽으로 가면, 1쪽 구분선은
        /// 가장 낮은 조각 아래 − 6, 2쪽은 문단 끝 캐시 30을 뺀다
        func testContinuedFragmentUsesItsOwnLastLineNotTheParagraphCache() async throws {
            var paragraph = try HwpSynthetic.textParagraph(
                String(repeating: "이어지는 캐시 문단 ", count: 12)
            )
            var payload = Data()
            for (index, spacing) in [1200, 1200, 1200, 1200, 3000].enumerated() {
                let line: [UInt32] = [
                    UInt32(index * 24), UInt32(index * 2200), 1000, 1000, 850, UInt32(spacing),
                    0, 42520, 393_216,
                ]
                for value in line {
                    withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
                }
            }
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
            // 본문 높이 6500 HWPUNIT = 65pt (위·아래 여백 20mm): 1단 앞 빈 문단(16) + 두 줄(44),
            // 2단 두 줄(44), 마지막 줄(40)은 2쪽
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 6500 + 5670 + 5670)),
                    .column(Self.column(divider: 1)),
                ],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let total = await paginator.totalPages()
            expect(total) >= 2
            let maybeFirst = try await paginator.page(at: 0)
            let first = try XCTUnwrap(maybeFirst)
            let fragments = first.blocks.filter { $0.kind == .text && $0.role == .body }
            let lowest = try XCTUnwrap(fragments.map(\.frame.maxY).max())
            let firstDivider = try XCTUnwrap(Self.dividers(in: first).first)
            expect(fragments.count) == 3
            expect(firstDivider.frame.maxY).to(beCloseTo(lowest - 6, within: 0.01))
            let maybeSecond = try await paginator.page(at: 1)
            let second = try XCTUnwrap(maybeSecond)
            let tail = try XCTUnwrap(second.blocks.first { $0.kind == .text && $0.role == .body })
            let secondDivider = try XCTUnwrap(Self.dividers(in: second).first)
            expect(secondDivider.frame.maxY).to(beCloseTo(tail.frame.maxY - 30, within: 0.01))
        }

        func testNoDividerWithoutLineTypeOrSecondColumn() async throws {
            let maybeNone = try await Self.page(column: Self.column(divider: 0), text: "본문")
            expect(Self.dividers(in: try XCTUnwrap(maybeNone))).to(beEmpty())
            var single = HwpSynthetic.column(count: 1)
            single.dividerType = 1
            let maybeOne = try await Self.page(column: single, text: "본문")
            expect(Self.dividers(in: try XCTUnwrap(maybeOne))).to(beEmpty())
        }

        /// 밴드가 쪽 끝으로 닫혀도 구분선은 한 번만 난다
        func testDividerIsEmittedOncePerBand() async throws {
            let paragraphs = try (0 ..< 6).map { _ in
                try HwpSynthetic.textParagraph(String(repeating: "가나다라마바사 ", count: 30))
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 30000)),
                    .column(Self.column(divider: 1)),
                ],
                bodyParagraphs: paragraphs
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let total = await paginator.totalPages()
            expect(total) >= 2
            for index in 0 ..< total {
                let maybePage = try await paginator.page(at: index)
                expect(Self.dividers(in: try XCTUnwrap(maybePage)).count) == 1
            }
        }
    }
#endif

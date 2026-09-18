@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 단 구분선 바닥이 빼는 마지막 줄 줄 간격의 출처 (#191, PR 리뷰) — 단별 줄 캐시 run·CT
    /// 폴백·수치 일치·재배치 조각. 헬퍼(`column(divider:)`·`dividers(in:)`)는 본 클래스의 것.
    extension HwpColumnDividerTests {
        /// 캐시 총높이(2줄 40 + 24 = 64pt)가 CT 총높이(4줄 16 × 4 = 64pt)와 우연히 같아도 높이
        /// 출처는 캐시다 — 문단을 끝내는 조각은 캐시 마지막 줄 간격 2를 빼야 한다 (PR 리뷰: 수치
        /// 일치로 판정하면 표식이 빠져 규칙값 6을 뺐다). 두 단 재배치 뒤 앞 조각(측정 2줄, 32 − 6)
        /// 보다 뒤 조각(잔여 − 2)의 글상자가 낮아 구분선이 거기서 끝난다.
        func testDividerUsesTheCacheSpacingWhenCacheAndMeasuredHeightsCoincide() async throws {
            var paragraph = try HwpSynthetic.textParagraph(
                String(repeating: "가나다라마 ", count: 14) // 10pt 네 줄 (207pt 단, 약 24자/줄)
            )
            var payload = Data()
            for line: [UInt32] in [
                [0, 0, 1000, 1000, 850, 3000, 0, 42520, 393_216],
                [70, 4000, 2200, 2200, 1870, 200, 0, 42520, 393_216],
            ] {
                for value in line {
                    withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
                }
            }
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
            paragraph.ctrlHeaderArray = [.column(Self.column(divider: 1))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let maybePage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(maybePage)
            let columns = page.blocks
                .filter { $0.attributedString?.string.contains("가나다라마") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(columns.count) == 2
            guard columns.count == 2 else { return }
            let front = columns[0], back = columns[1]
            // 앞 조각 = 측정 2줄(32), 뒤 조각 = 캐시 잔여(64 − 32)
            expect(front.frame.height).to(beCloseTo(32, within: 0.01))
            expect(back.frame.height).to(beCloseTo(32, within: 0.01))
            let divider = try XCTUnwrap(Self.dividers(in: page).first)
            expect(divider.frame.maxY).to(beCloseTo(back.frame.maxY - 2, within: 0.01))
            expect(back.frame.maxY - 2) > front.frame.maxY - 6
        }

        /// 재배치가 뒤 조각을 **폭이 다른 단**으로 옮겨 CT로 다시 재면 그 높이는 캐시가 아니다 —
        /// 캐시(2줄 40 + 24)와 CT(넓은 단 4줄 16 × 4)의 총높이가 같은 문단을 비등폭 2단에 나누면
        /// 좁은 단의 뒤 조각(2줄 몫)은 4줄 64pt로 다시 재어지고, 구분선은 캐시 간격 2가 아니라
        /// 측정 간격 6을 뺀다 (PR 리뷰: 표식이 남아 4pt 낮은 자리에서 끝났다)
        func testRemeasuredBackFragmentDropsTheInheritedCacheSpacing() async throws {
            var paragraph = try HwpSynthetic.textParagraph(
                String(repeating: "가나다라마 ", count: 20) // 넓은 단(279pt, 약 34자/줄)에서 네 줄
            )
            var payload = Data()
            for line: [UInt32] in [
                [0, 0, 1000, 1000, 850, 3000, 0, 42520, 393_216],
                [42, 4000, 2200, 2200, 1870, 200, 0, 42520, 393_216],
            ] {
                for value in line {
                    withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
                }
            }
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
            // 비등폭 2단: 넓은 첫 단(2/3) + 좁은 둘째 단(1/3), 구분선 실선
            var column = HwpSynthetic.column(count: 2, widths: [21000, 9000], gaps: [2000, 0])
            column.dividerType = 1
            column.dividerThickness = 1
            column.dividerColor = CoreHwp.HwpColor(255, 0, 0)
            paragraph.ctrlHeaderArray = [.column(column)]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let maybePage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(maybePage)
            let columns = page.blocks
                .filter { $0.attributedString?.string.contains("가나다라마") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(columns.count) == 2
            guard columns.count == 2 else { return }
            let front = columns[0], back = columns[1]
            expect(back.frame.width) < front.frame.width
            // 앞 조각 = 넓은 단 2줄(32), 뒤 조각 = 좁은 단(약 120pt)에서 다시 재어 4줄(64)
            expect(front.frame.height).to(beCloseTo(32, within: 0.01))
            expect(back.frame.height).to(beCloseTo(64, within: 0.01))
            let divider = try XCTUnwrap(Self.dividers(in: page).first)
            expect(divider.frame.maxY).to(beCloseTo(back.frame.maxY - 6, within: 0.01))
        }

        /// 단 균형 재배치(`rebalancedFragment`)로 나뉜 앞 조각은 문단 마지막 줄의 캐시 줄 간격
        /// 표식을 물려받으면 안 된다 — 세 줄 캐시 문단(줄 간격 12·12·30)을 두 단에 나누면 앞
        /// 조각(측정 2줄)은 규칙값 6, 뒤 조각(캐시 잔여, 문단 끝)은 캐시 30을 뺀다 (PR 리뷰: 앞
        /// 조각에서 30을 빼 구분선이 짧아졌다)
        func testRebalancedFrontFragmentDropsTheInheritedCacheSpacing() async throws {
            var paragraph = try HwpSynthetic.textParagraph(
                String(repeating: "가나다라마 ", count: 15) // 10pt 세 줄 (207pt 단, 약 41자/줄)
            )
            var payload = Data()
            for (index, spacing) in [1200, 1200, 3000].enumerated() {
                let line: [UInt32] = [
                    UInt32(index * 18), UInt32(index * 2200), 1000, 1000, 850, UInt32(spacing),
                    0, 42520, 393_216,
                ]
                for value in line {
                    withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
                }
            }
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
            paragraph.ctrlHeaderArray = [.column(Self.column(divider: 1))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let maybePage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(maybePage)
            let columns = page.blocks
                .filter { $0.attributedString?.string.contains("가나다라마") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(columns.count) == 2
            guard columns.count == 2 else { return }
            let front = columns[0], back = columns[1]
            // 세 줄을 두 단에 2 + 1로 — 앞 조각 = 측정 줄 2개(32pt), 뒤 조각 = 캐시 잔여
            // (84 − 32 = 52pt)
            expect(front.frame.height).to(beCloseTo(32, within: 0.01))
            expect(back.frame.height).to(beCloseTo(52, within: 0.01))
            let divider = try XCTUnwrap(Self.dividers(in: page).first)
            // 앞 조각 글상자 아래(32 − 6 = 26)가 뒤 조각(52 − 30 = 22)보다 낮다 — 앞 조각이
            // 30을 물려받았다면 22에서 끝난다
            expect(divider.frame.maxY).to(beCloseTo(front.frame.maxY - 6, within: 0.01))
            expect(front.frame.maxY - 6) > back.frame.maxY - 30
        }

        /// 캐시 높이가 단 높이를 넘는 1줄 문단은 CT 측정 높이로 폴백해 놓인다 — 그 블록의 구분선은
        /// 버린 캐시의 줄 간격(12pt)이 아니라 측정 줄 간격(6pt)을 빼야 한다 (PR 리뷰: 16pt 블록에서
        /// 구분선이 4pt만 그려졌다)
        func testDividerUsesMeasuredSpacingWhenTheCacheHeightWasDiscarded() async throws {
            var paragraph = try HwpSynthetic.textParagraph("한 줄")
            var payload = Data()
            // 표 40: 줄 높이 8000(80pt) + 줄 간격 1200(12pt) — 본문 65pt를 넘는 1줄 캐시
            for value: UInt32 in [0, 0, 8000, 8000, 6800, 1200, 0, 42520, 393_216] {
                withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
            }
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
            // 단 정의를 이 문단에 붙여 밴드에 이 블록만 들게 한다 (앞 빈 문단과 바닥이 겹치지 않게)
            paragraph.ctrlHeaderArray = [.column(Self.column(divider: 1))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 6500 + 5670 + 5670)),
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
            let text = try XCTUnwrap(page.blocks.first { $0.attributedString?.string == "한 줄" })
            expect(text.frame.height).to(beCloseTo(16, within: 0.01)) // CT 10pt × 160%
            let divider = try XCTUnwrap(Self.dividers(in: page).first)
            expect(divider.frame.minY).to(beCloseTo(text.frame.minY, within: 0.01))
            expect(divider.frame.maxY).to(beCloseTo(text.frame.maxY - 6, within: 0.01))
        }

        /// 한글이 단별 run으로 저장한 정상 다단 캐시(단 경계마다 `lineLocation` 0 리셋)는 문단
        /// 전체의 단조 증가 검사에 걸리지만 블록은 캐시 높이로 놓인다(`placeCachedColumnRuns`) —
        /// 구분선도 그 run 마지막 줄의 캐시 줄 간격(12pt, 규칙값 6pt와 다름)을 빼야 한다 (PR 리뷰)
        func testDividerBottomUsesTheColumnRunCacheSpacing() async throws {
            let text = String(repeating: "가나다라 ", count: 8) // 40자
            var paragraph = try HwpSynthetic.columnCacheParagraph(text, segments: [
                .init(textIndex: 0, location: 0, height: 1000, width: 13416),
                .init(textIndex: 10, location: 2200, height: 1000, width: 13416),
                .init(textIndex: 20, location: 0, height: 1000, width: 13416),
                .init(textIndex: 30, location: 2200, height: 1000, width: 13416),
            ])
            // 줄 간격을 600(6pt)에서 1200(12pt)으로 — 표 40의 여섯째 필드 (36바이트 레코드)
            var payload = Data()
            for (index, textIndex) in [UInt32(0), 10, 20, 30].enumerated() {
                let line: [UInt32] = [
                    textIndex, UInt32(index % 2 == 0 ? 0 : 2200), 1000, 1000, 850, 1200,
                    0, 13416, 393_216,
                ]
                for value in line {
                    withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
                }
            }
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
            paragraph.ctrlHeaderArray = [.column(Self.column(divider: 1))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let maybePage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(maybePage)
            let columns = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("가나") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(columns.count) == 2
            // 두 run 모두 캐시 높이 (2200 + 1000 + 1200) = 44pt로 놓인다
            for column in columns {
                expect(column.frame.height).to(beCloseTo(44, within: 0.01))
            }
            let lowest = try XCTUnwrap(columns.map(\.frame.maxY).max())
            let divider = try XCTUnwrap(Self.dividers(in: page).first)
            expect(divider.frame.maxY).to(beCloseTo(lowest - 12, within: 0.01))
        }
    }
#endif

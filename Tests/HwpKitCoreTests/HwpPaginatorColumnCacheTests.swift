@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 한글 라인 캐시 기반 단 배분 (loc 리셋 = 단 경계)과 밴드 간 줄 간격,
    /// 글자처럼 취급 표의 인라인 앵커 배치 테스트 (Column/noori PrvImage 실측 동작).
    final class HwpPaginatorColumnCacheTests: XCTestCase {
        private func firstPage(
            of section: CoreHwp.HwpSection
        ) async throws -> HwpPage? {
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            return try await paginator.page(at: 0)
        }

        /// 비등폭 2단에서 캐시 run 경계 (textStartingIndex)대로 텍스트가
        /// 좁은 단/넓은 단에 배분된다 — 라인 수 균등 분배가 아니다.
        func testCachedRunsDistributeTextByCharPosition() async throws {
            let words = (0 ..< 18).map { "word\($0)" }
            let text = words.joined(separator: " ") // 125자
            let textCount = UInt32(text.utf16.count)
            // 좁은 단 (약 1/3 폭)에 앞 1/3, 넓은 단에 나머지 (Column p3 패턴)
            let boundary = textCount / 3
            var paragraph = try HwpSynthetic.columnCacheParagraph(text, segments: [
                .init(textIndex: 0, location: 0, height: 1500, width: 13416),
                .init(textIndex: boundary / 2, location: 2552, height: 1500, width: 13416),
                .init(textIndex: boundary, location: 0, height: 1500, width: 26837),
                .init(textIndex: boundary + 20, location: 2552, height: 1500, width: 26837),
            ])
            // Column 픽스처 패턴: 단 정의가 해당 문단에 부착 → 문단 시작 = 새 밴드
            paragraph.ctrlHeaderArray = [.column(HwpSynthetic.column(
                count: 2,
                widths: [10339, 20682],
                gaps: [1747, 0]
            ))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )

            guard let page = try await firstPage(of: section) else {
                fail("첫 페이지가 없다")
                return
            }
            let textBlocks = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("word") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(textBlocks.count) == 2

            guard textBlocks.count == 2,
                  let leftText = textBlocks[0].attributedString?.string,
                  let rightText = textBlocks[1].attributedString?.string
            else { return }
            // 두 단이 서로 다른 프레임에서 시작하고 원문을 나눠 담는다
            expect(textBlocks[1].frame.minX) > textBlocks[0].frame.maxX - 1
            expect(leftText + rightText) == text
            // 경계는 캐시 비례 위치 (1/3) 근처의 CT 라인 시작으로 스냅된다
            let leftCount = Double(leftText.utf16.count)
            expect(leftCount) > Double(textCount) / 6
            expect(leftCount) < Double(textCount) * 2 / 3
            // 각 단 블록 높이 = run의 캐시 높이 (loc 2552 + 1500 + 600 = 46.52pt)
            expect(textBlocks[0].frame.height).to(beCloseTo(46.52, within: 0.5))
            expect(textBlocks[1].frame.height).to(beCloseTo(46.52, within: 0.5))
            // 같은 밴드: 두 단의 시작 y가 같다
            expect(textBlocks[0].frame.minY).to(beCloseTo(textBlocks[1].frame.minY, within: 0.5))
        }

        /// 단 정의로 밴드를 닫으면 다음 밴드는 마지막 줄의 줄 간격만큼 띄운 뒤
        /// 시작한다 (Column PrvImage 실측: 밴드 간 시작 간격 = 줄 전진량 + 줄 간격).
        func testColumnBandGapAddsTrailingLineSpacing() async throws {
            // 캐시 두 줄 (h 1000 + sp 600 → 블록 32pt), 그다음 밴드 시작
            var first = try HwpSynthetic.lineSegParagraph(
                "첫 밴드 문단",
                segments: [(location: 0, height: 1000), (location: 1600, height: 1000)]
            )
            first.ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
            var second = try HwpSynthetic.lineSegParagraph(
                "둘째 밴드 문단",
                segments: [(location: 0, height: 1000)]
            )
            second.ctrlHeaderArray = [.column(HwpSynthetic.column(count: 1))]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [first, second]
            )

            guard let page = try await firstPage(of: section) else {
                fail("첫 페이지가 없다")
                return
            }
            let blocks = page.blocks
                .filter { $0.attributedString?.string.contains("밴드 문단") == true }
                .sorted { $0.frame.minY < $1.frame.minY }
            expect(blocks.count) == 2
            guard blocks.count == 2 else { return }
            // 32pt (캐시 높이) + 6pt (마지막 줄 간격 600)
            expect(blocks[1].frame.minY - blocks[0].frame.minY)
                .to(beCloseTo(38, within: 0.5))
        }

        /// 글자처럼 취급 표는 FFFC 앵커 줄 위치에 배치되고 흐름 높이를 추가로
        /// 소비하지 않는다 (noori 보도자료 표 실측: 캐시 줄 높이 = 표 높이).
        func testTreatAsCharTableAnchorsToItsLine() async throws {
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "앞 ", suffix: " 뒤")
            var table = HwpSynthetic.table(
                cellWidth: 20000,
                rowHeights: [10000],
                cellParagraphs: [[[try HwpSynthetic.textParagraph("셀")]]]
            )
            table.commonCtrlProperty.width = 20000
            table.commonCtrlProperty.height = 10000
            table.commonCtrlProperty.instanceId = 7
            var info = CoreHwp.HwpCommonCtrlPropertyInfo()
            info.treatAsChar = true
            table.commonCtrlProperty.propertyInfo = info
            host.ctrlHeaderArray = [.table(table)]

            let follower = try HwpSynthetic.textParagraph("다음 문단")
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef()),
                    .column(CoreHwp.HwpColumn()),
                ],
                bodyParagraphs: [host, follower]
            )

            guard let page = try await firstPage(of: section) else {
                fail("첫 페이지가 없다")
                return
            }
            guard let hostBlock = page.blocks.first(where: {
                $0.kind == .text && $0.attributedString?.string.contains("앞") == true
            }) else {
                fail("호스트 문단 블록이 없다")
                return
            }
            guard let tableBlock = page.blocks.first(where: {
                $0.kind == .table && $0.source?.controlInstanceId == 7
            }) else {
                fail("인라인 표 블록이 없다")
                return
            }
            guard let followerBlock = page.blocks.first(where: {
                $0.attributedString?.string.contains("다음 문단") == true
            }) else {
                fail("후속 문단 블록이 없다")
                return
            }

            // 표(100pt)가 줄에서 가장 크므로 표 위 == 앵커 줄 위 == 블록 위
            expect(tableBlock.frame.minY).to(beCloseTo(hostBlock.frame.minY, within: 1))
            expect(tableBlock.frame.height).to(beCloseTo(100, within: 1))
            // 줄 공간은 run delegate가 예약: 호스트 블록이 표 높이를 포함하고,
            // 후속 문단은 표 높이를 이중 소비하지 않고 바로 아래에서 시작한다
            expect(hostBlock.frame.height) >= 100
            expect(followerBlock.frame.minY - hostBlock.frame.minY) < 150
        }
    }
#endif

@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 절대 캐시 모드의 CT 측정 생략 게이트 검증 — 생략이 적용되는 일반
    /// 문단의 절단·좌표가 불변이고, CT 산출물이 필요한 문단 (인라인 앵커·
    /// stale 캐시)은 게이트가 CT를 유지하는지 확인한다.
    final class HwpPaginatorAbsoluteCacheSkipTests: XCTestCase {
        private func paginate(_ section: CoreHwp.HwpSection) -> HwpPaginator {
            HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        func testPlainParagraphsKeepAbsolutePlacementAndPageSplit() async throws {
            // 페이지당 3줄 wrap — 절대 y 리셋마다 페이지가 갈라져야 한다
            let locations: [Int32] = [2720, 4820, 6920, 2720, 4820]
            let bodyParagraphs = try locations.enumerated().map { index, location in
                try HwpSynthetic.lineSegParagraph(
                    "절대 문단 \(index)",
                    segments: [(location: location, height: 1500)]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: bodyParagraphs
            )
            let paginator = paginate(section)

            let totalPages = await paginator.totalPages()
            expect(totalPages) == 2

            let first = try await paginator.page(at: 0)
            let firstBlocks = (first?.blocks ?? []).filter {
                $0.attributedString?.string.contains("절대") == true
            }
            expect(firstBlocks.count) == 3
            let contentTop = first?.margins.top ?? 0
            for (offset, block) in firstBlocks.enumerated() {
                // 한글 캐시 y 그대로: contentTop + loc(HWPUNIT)/100
                let expectedY = contentTop + CGFloat(2720 + offset * 2100) / 100
                expect(block.frame.minY).to(beCloseTo(expectedY, within: 0.01))
                // 줄 전진량 = h(1500) + sp(600) = 21pt
                expect(block.frame.height).to(beCloseTo(21, within: 0.01))
            }

            let second = try await paginator.page(at: 1)
            let secondBlocks = (second?.blocks ?? []).filter {
                $0.attributedString?.string.contains("절대") == true
            }
            expect(secondBlocks.count) == 2
        }

        func testInlineObjectParagraphKeepsAnchorMeasurement() async throws {
            // controlIndex 마커가 있는 문단은 CT 생략 게이트에서 제외돼
            // 인라인 앵커 좌표 (lines의 inlineAnchors)가 계속 계산돼야 한다.
            var host = HwpSynthetic.paragraphWithInlineControl(prefix: "본문 ", suffix: " 끝")
            host.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.inlineShapeObject(
                    width: 5000,
                    height: 2000,
                    instanceId: 77
                )),
            ]
            host.paraLineSeg = try HwpSynthetic.lineSegParagraph(
                "자리", segments: [(location: 4820, height: 1500)]
            ).paraLineSeg
            let plain = { location in
                try HwpSynthetic.lineSegParagraph(
                    "일반 문단",
                    segments: [(location: location, height: 1500)]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [try plain(2720), host, try plain(6920)]
            )
            let paginator = paginate(section)

            let page = try await paginator.page(at: 0)
            let objectBlock = page?.blocks.first { $0.source?.controlInstanceId == 77 }

            expect(objectBlock).toNot(beNil())
            // 앵커가 자기 줄 (loc 4820 = 48.2pt + contentTop) 근처에 놓인다
            let contentTop = page?.margins.top ?? 0
            expect(objectBlock?.frame.minY ?? -1)
                .to(beGreaterThan(contentTop + 30))
        }

        func testStaleCacheParagraphKeepsHeightCorrection() async throws {
            // 캐시 줄 높이 (5pt) < 글자 크기 → stale 보정이 CT 높이로
            // 슬롯을 넓혀야 한다 (advance 5+6 = 11pt보다 커야 함).
            let stale = try HwpSynthetic.lineSegParagraph(
                "스테일 캐시 문단",
                segments: [(location: 2720, height: 500)]
            )
            let plain = try HwpSynthetic.lineSegParagraph(
                "일반 문단",
                segments: [(location: 6920, height: 1500)]
            )
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [stale, plain]
            )
            let paginator = paginate(section)

            let page = try await paginator.page(at: 0)
            let staleBlock = page?.blocks.first {
                $0.attributedString?.string.contains("스테일") == true
            }

            expect(staleBlock).toNot(beNil())
            expect(staleBlock?.frame.height ?? 0).to(beGreaterThan(11.5))
        }
    }
#endif

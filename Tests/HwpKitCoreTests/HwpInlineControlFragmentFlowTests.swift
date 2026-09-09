import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 라인 캐시 없는 흐름 분할(`appendParagraphAcrossColumns`)의 조각별 글자처럼 취급 표 배치 (#164) —
    /// 절대 캐시 run은 `HwpInlineControlFragmentTests`, 다단 캐시 run은 `…ColumnTests`.
    final class HwpInlineControlFragmentFlowTests: XCTestCase {
        private static func inlineTable(instanceId: UInt32) throws -> CoreHwp.HwpCtrlId {
            try InlineControlFragmentSupport.inlineTable(instanceId: instanceId)
        }

        private static func objectBlocks(on page: HwpPage, instanceId: UInt32) -> [AnyHwpBlock] {
            InlineControlFragmentSupport.objectBlocks(on: page, instanceId: instanceId)
        }

        private static func hostFragment(on page: HwpPage) -> AnyHwpBlock? {
            InlineControlFragmentSupport.hostFragment(on: page)
        }

        private static func pages(of paginator: HwpPaginator) async throws -> [HwpPage] {
            try await InlineControlFragmentSupport.pages(of: paginator)
        }

        /// 라인 캐시 없이 한 쪽보다 긴 문단(`appendParagraphAcrossColumns`)도 앞 조각의
        /// 표를 앞 쪽의 조각 줄 안에, 뒤 조각의 표를 뒤 쪽에 놓는다.
        func testFlowSplitParagraphPlacesInlineTablesPerFragment() async throws {
            // 첫 줄 끝과 마지막 줄 끝에 마커, 사이에 빈 줄 70개 — A4 본문(약 700pt)보다 길다.
            var host = try HwpSynthetic.splitParagraphWithControlMarkers(
                lines: [(characters: 5, marker: true)]
                    + Array(repeating: (characters: 5, marker: false), count: 70)
                    + [(characters: 5, marker: true)],
                segments: [],
                markerCode: 11
            )
            host.ctrlHeaderArray = [
                try Self.inlineTable(instanceId: 1),
                try Self.inlineTable(instanceId: 2),
            ]
            let follower = try HwpSynthetic.textParagraph("뒤 문단")
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [host, follower]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let pages = try await Self.pages(of: paginator)
            // 흐름 배치는 구역 첫 문단 뒤에 안 들어가는 문단을 새 쪽으로 옮기므로
            // 첫 쪽엔 구역 첫 문단만 남고, 긴 문단은 둘째·셋째 쪽에 갈린다.
            expect(pages.count) == 3
            guard pages.count == 3 else { return }

            let first = try XCTUnwrap(Self.objectBlocks(on: pages[1], instanceId: 1).first)
            let firstHost = try XCTUnwrap(Self.hostFragment(on: pages[1]))
            let second = try XCTUnwrap(Self.objectBlocks(on: pages[2], instanceId: 2).first)
            let secondHost = try XCTUnwrap(Self.hostFragment(on: pages[2]))
            expect(first.frame.minY).to(beGreaterThanOrEqualTo(firstHost.frame.minY - 0.01))
            expect(first.frame.maxY).to(beLessThanOrEqualTo(firstHost.frame.maxY + 0.01))
            expect(first.frame.minX) > firstHost.frame.minX + 1
            expect(second.frame.minY).to(beGreaterThanOrEqualTo(secondHost.frame.minY - 0.01))
            expect(second.frame.maxY).to(beLessThanOrEqualTo(secondHost.frame.maxY + 0.01))
            expect(pages.flatMap { Self.objectBlocks(on: $0, instanceId: 1) }.count) == 1
            expect(pages.flatMap { Self.objectBlocks(on: $0, instanceId: 2) }.count) == 1
            expect(Self.objectBlocks(on: pages[1], instanceId: 2)).to(beEmpty())
            // 뒤 문단은 마지막 조각 아래 흐름 자리 그대로다.
            let followerBlock = try XCTUnwrap(pages[2].blocks.first {
                $0.attributedString?.string.contains("뒤 문단") == true
            })
            expect(followerBlock.frame.minY)
                .to(beGreaterThanOrEqualTo(secondHost.frame.maxY - 0.01))
        }

        /// 흐름 분할에서 뒤 조각의 **첫 줄**이 큰 줄 안 개체를 품으면, 그 줄의 ascent가
        /// 앞 조각 마지막 전진량에 실려 뒤 조각이 짧게 재어졌다 — 개체가 줄 안에 놓이면서
        /// 조각 블록 밖으로 나가고 뒤 문단이 그 위에 놓였다. 첫 줄 ascent 초과분을 뒤
        /// 조각으로 옮겨 블록이 개체와 줄을 다 담고, 뒤 문단은 그 아래에서 시작한다.
        func testFlowSplitFragmentStartingWithTallObjectContainsIt() async throws {
            // 평문 줄 열 개 뒤 열한째 줄에 100pt 표 — 본문 높이를 줄 열이 들어가고 표 줄로
            // 가는 전진량은 안 들어가는 크기로 잡아 표 줄이 다음 쪽 조각의 첫 줄이 되게 한다.
            let tall = try InlineControlFragmentSupport.inlineTable(instanceId: 9, height: 10000)
            var host = try HwpSynthetic.splitParagraphWithControlMarkers(
                lines: Array(repeating: (characters: 5, marker: false), count: 10)
                    + [(characters: 5, marker: true)]
                    + Array(repeating: (characters: 5, marker: false), count: 3),
                segments: [],
                markerCode: 11
            )
            host.ctrlHeaderArray = [tall]
            let follower = try HwpSynthetic.textParagraph("뒤 문단")
            // 본문 270pt = 쪽 높이 − 위/아래 여백(9920): 긴 문단은 새 쪽으로 옮겨져 줄
            // 열 개(전진량 아홉 × 17.36pt + 표 줄로 가는 전진량 약 107pt = 263pt)는 들어가고
            // 표 줄 다음 전진량은 안 들어가며, 그 다음 쪽은 표 줄(100pt)·남은 줄 셋·뒤
            // 문단을 다 담는다.
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 9920 + 27000)),
                ],
                bodyParagraphs: [host, follower]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let pages = try await Self.pages(of: paginator)
            let tablePage = try XCTUnwrap(pages.firstIndex {
                !Self.objectBlocks(on: $0, instanceId: 9).isEmpty
            })
            let table = try XCTUnwrap(Self.objectBlocks(on: pages[tablePage], instanceId: 9).first)
            let fragment = try XCTUnwrap(Self.hostFragment(on: pages[tablePage]))
            // 표 줄이 조각의 첫 줄이고, 조각 블록이 표(100pt)를 다 담는다.
            expect(table.frame.minY).to(beCloseTo(fragment.frame.minY, within: 0.01))
            expect(table.frame.maxY).to(beLessThanOrEqualTo(fragment.frame.maxY + 0.01))
            // 뒤 문단은 조각 블록 아래에서 시작한다 (표와 겹치지 않는다).
            let followerBlock = try XCTUnwrap(pages[tablePage].blocks.first {
                $0.attributedString?.string.contains("뒤 문단") == true
            })
            expect(followerBlock.frame.minY).to(beGreaterThanOrEqualTo(fragment.frame.maxY - 0.01))
            expect(followerBlock.frame.minY).to(beGreaterThanOrEqualTo(table.frame.maxY - 0.01))
        }
    }
#endif

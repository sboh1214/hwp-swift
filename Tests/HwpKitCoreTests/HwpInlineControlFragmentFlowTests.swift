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

        /// 라인 캐시 없는 문단이 비등폭 단(134.16 → 268.37pt)으로 이월되면 렌더러는 뒤
        /// 단 폭으로 다시 줄바꿈하므로, 조각의 앵커도 그 단 폭으로 다시 조판한 줄에서
        /// 찾는다 — 첫 단 폭의 줄로 잡으면 마커가 다른 줄·다른 x에 놓여 표가 글자를 덮는다.
        func testFlowSplitAnchorsFollowTheDestinationColumnWidth() async throws {
            let prefix = (0 ..< 40).map { "word\($0)" }.joined(separator: " ") + " "
            let suffix = " " + (40 ..< 46).map { "word\($0)" }.joined(separator: " ")
            var paragraph = HwpSynthetic.paragraphWithInlineControl(prefix: prefix, suffix: suffix)
            paragraph.ctrlHeaderArray = [
                try Self.inlineTable(instanceId: 7),
                .column(HwpSynthetic.column(count: 2, widths: [10339, 20682], gaps: [1747, 0])),
            ]
            // 본문 200pt: 좁은 첫 단(134pt, 줄당 세 단어)은 줄 열하나(33단어)라 마커는 넓은
            // 둘째 단으로 넘어간다.
            let section = HwpSynthetic.section(
                firstParagraphControls: [
                    .section(HwpSynthetic.sectionDef(pageHeight: 9920 + 20000)),
                ],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let pages = try await Self.pages(of: paginator)
            let tablePage = try XCTUnwrap(pages.firstIndex {
                !Self.objectBlocks(on: $0, instanceId: 7).isEmpty
            })
            let page = pages[tablePage]
            let table = try XCTUnwrap(Self.objectBlocks(on: page, instanceId: 7).first)
            let host = try XCTUnwrap(page.blocks.first {
                $0.kind == .text && $0.attributedString?.string.contains("\u{FFFC}") == true
                    && $0.source?.paragraphIndex == 1
            })
            // 마커가 든 조각은 넓은 단(268.37pt)에 있고, 표는 그 조각 블록 안 **그려지는
            // 마커의 줄**에 있다 — 첫 단 폭의 줄로 잡으면 단 왼쪽 끝(x 241.87)의 다음 줄에
            // 놓여 글자를 덮었다. x는 양쪽 정렬 재조판 몫만큼 갈릴 수 있어 줄 안 위치로만 본다.
            expect(host.frame.width).to(beCloseTo(268.37, within: 0.5))
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(host.frame.minY - 0.01))
            expect(table.frame.maxY).to(beLessThanOrEqualTo(host.frame.maxY + 0.01))
            let drawn = try XCTUnwrap(InlineControlFragmentSupport.drawnMarker(
                in: try XCTUnwrap(host.attributedString),
                origin: host.frame.origin,
                lineWidth: host.frame.width,
                controlIndex: 0
            ))
            expect(table.frame.minY).to(beCloseTo(drawn.baselineY - 10, within: 2))
            expect(table.frame.minX).to(beGreaterThan(host.frame.minX + 20))
            expect(table.frame.minX).to(beLessThanOrEqualTo(drawn.x + 0.5))
            expect(pages.flatMap { Self.objectBlocks(on: $0, instanceId: 7) }.count) == 1
        }
    }
#endif

import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 다단 캐시 run(단 경계)의 조각별 글자처럼 취급 표 배치와 조각 줄 프레임 (#164) —
    /// 쪽 경계(절대 캐시·흐름 분할)는 `HwpInlineControlFragmentTests`.
    final class HwpInlineControlFragmentColumnTests: XCTestCase {
        private static func inlineTable(instanceId: UInt32) throws -> CoreHwp.HwpCtrlId {
            try InlineControlFragmentSupport.inlineTable(instanceId: instanceId)
        }

        private static func objectBlocks(on page: HwpPage, instanceId: UInt32) -> [AnyHwpBlock] {
            InlineControlFragmentSupport.objectBlocks(on: page, instanceId: instanceId)
        }

        // MARK: 다단 캐시 run (단 경계)

        /// 한글 캐시가 단별 run으로 나눈 문단(`placeCachedColumnRuns`)의 앞 단 표는 앞 단의
        /// 조각 줄 안에 놓인다 — 마지막 단의 문맥만 남으면 앞 단의 표가 앵커를 잃고 마지막
        /// 단 블록 뒤 흐름 위치로 갔다.
        func testCachedColumnRunsPlaceInlineTableInItsColumn() async throws {
            let prefix = "word0 word1 "
            let suffix = (2 ..< 18).map { "word\($0)" }.joined(separator: " ")
            let text = prefix + "X" + suffix
            // 컨트롤 문자는 WCHAR 스트림에서 8이라 헤더 글자 수도 그만큼 늘린다.
            let streamCount = UInt32(prefix.utf16.count + 8 + suffix.utf16.count)
            let boundary = streamCount / 3
            var paragraph = try HwpSynthetic.columnCacheParagraph(text, segments: [
                .init(textIndex: 0, location: 0, height: 1500, width: 13416),
                .init(textIndex: boundary / 2, location: 2552, height: 1500, width: 13416),
                .init(textIndex: boundary, location: 0, height: 1500, width: 26837),
                .init(textIndex: boundary + 20, location: 2552, height: 1500, width: 26837),
            ], charCount: streamCount)
            paragraph.paraText = HwpSynthetic.paragraphWithInlineControl(
                prefix: prefix, suffix: suffix
            ).paraText
            // 표는 마커 서수 0에 맞춰 첫 컨트롤이어야 한다 — 단 정의는 마커가 없다.
            paragraph.ctrlHeaderArray = [
                try Self.inlineTable(instanceId: 5),
                .column(HwpSynthetic.column(count: 2, widths: [10339, 20682], gaps: [1747, 0])),
            ]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)

            let columns = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("word") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(columns.count) == 2
            guard columns.count == 2 else { return }
            let table = try XCTUnwrap(Self.objectBlocks(on: page, instanceId: 5).first)
            // 표는 왼쪽 단(첫 run) 블록 안에 있다 — 오른쪽 단 블록 뒤가 아니다.
            expect(table.frame.minX).to(beGreaterThanOrEqualTo(columns[0].frame.minX - 0.01))
            expect(table.frame.minX) < columns[1].frame.minX
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(columns[0].frame.minY - 0.01))
            expect(table.frame.maxY).to(beLessThanOrEqualTo(columns[0].frame.maxY + 0.01))
            expect(Self.objectBlocks(on: page, instanceId: 5).count) == 1
        }

        /// 비등폭 단의 뒤 단은 첫 단 폭으로 잰 줄과 다르게 조판되므로, 조각 문자열을 그 단
        /// 폭으로 다시 조판한 줄이 앵커 문맥이다 — 표는 뒤 단 블록 안, 그려지는 마커 자리에
        /// 놓인다 (첫 단 폭의 줄로 잡으면 다른 줄·다른 x에 놓여 글자를 덮는다).
        func testCachedColumnRunsRelayoutAnchorsInAColumnOfDifferentWidth() async throws {
            let prefix = (0 ..< 14).map { "word\($0)" }.joined(separator: " ") + " "
            let suffix = (14 ..< 18).map { "word\($0)" }.joined(separator: " ")
            let text = prefix + "X" + suffix
            let streamCount = UInt32(prefix.utf16.count + 8 + suffix.utf16.count)
            let boundary = streamCount / 3
            var paragraph = try HwpSynthetic.columnCacheParagraph(text, segments: [
                .init(textIndex: 0, location: 0, height: 1500, width: 13416),
                .init(textIndex: boundary / 2, location: 2552, height: 1500, width: 13416),
                .init(textIndex: boundary, location: 0, height: 1500, width: 26837),
                .init(textIndex: boundary + 20, location: 2552, height: 1500, width: 26837),
            ], charCount: streamCount)
            paragraph.paraText = HwpSynthetic.paragraphWithInlineControl(
                prefix: prefix, suffix: suffix
            ).paraText
            paragraph.ctrlHeaderArray = [
                try Self.inlineTable(instanceId: 6),
                .column(HwpSynthetic.column(count: 2, widths: [10339, 20682], gaps: [1747, 0])),
            ]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)
            let columns = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("word") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(columns.count) == 2
            guard columns.count == 2 else { return }
            // 마커는 뒤 단(넓은 단) 텍스트에 있다.
            expect(columns[1].attributedString?.string.contains("\u{FFFC}")) == true
            let table = try XCTUnwrap(Self.objectBlocks(on: page, instanceId: 6).first)
            expect(Self.objectBlocks(on: page, instanceId: 6).count) == 1
            // 뒤 단 블록 안, 렌더러가 그 단 폭으로 다시 조판한 마커 자리에 있다.
            expect(table.frame.minY).to(beGreaterThanOrEqualTo(columns[1].frame.minY - 0.01))
            expect(table.frame.maxY).to(beLessThanOrEqualTo(columns[1].frame.maxY + 0.01))
            let drawn = try XCTUnwrap(InlineControlFragmentSupport.drawnMarker(
                in: try XCTUnwrap(columns[1].attributedString),
                origin: columns[1].frame.origin,
                lineWidth: columns[1].frame.width,
                controlIndex: 0
            ))
            expect(table.frame.minX).to(beCloseTo(drawn.x, within: 0.5))
            // 표(10pt) 위 = 마커 줄 baseline − ascent (개체 줄의 baseline 들어올림 안).
            expect(table.frame.minY).to(beCloseTo(drawn.baselineY - 10, within: 2))
        }

        /// 단 기준 상대 크기 개체가 폭이 다른 단으로 이월되면 예약 폭도 그 단으로 다시
        /// 푼다 — 처음 잰 단의 예약(단 너비 50% = 67.08pt)이 남으면 목적 단으로 크기를
        /// 푸는 paint(134.19pt)와 갈려 개체가 뒤 글자를 67pt 덮는다 (PR 리뷰).
        func testCachedColumnRunsRescaleColumnRelativeReservation() async throws {
            let prefix = (0 ..< 14).map { "word\($0)" }.joined(separator: " ") + " "
            let suffix = (14 ..< 18).map { "word\($0)" }.joined(separator: " ")
            let text = prefix + "X" + suffix
            let streamCount = UInt32(prefix.utf16.count + 8 + suffix.utf16.count)
            let boundary = streamCount / 3
            var paragraph = try HwpSynthetic.columnCacheParagraph(text, segments: [
                .init(textIndex: 0, location: 0, height: 1500, width: 13416),
                .init(textIndex: boundary / 2, location: 2552, height: 1500, width: 13416),
                .init(textIndex: boundary, location: 0, height: 1500, width: 26837),
                .init(textIndex: boundary + 20, location: 2552, height: 1500, width: 26837),
            ], charCount: streamCount)
            paragraph.paraText = HwpSynthetic.paragraphWithInlineControl(
                prefix: prefix, suffix: suffix
            ).paraText
            paragraph.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.columnRelativeInlineObject(
                    widthPercent: 5000, heightPercent: 200, instanceId: 8
                )),
                .column(HwpSynthetic.column(count: 2, widths: [10339, 20682], gaps: [1747, 0])),
            ]
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef())],
                bodyParagraphs: [paragraph]
            )
            let paginator = HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            let rendered = try await paginator.page(at: 0)
            let page = try XCTUnwrap(rendered)
            let columns = page.blocks
                .filter { $0.kind == .text && $0.attributedString?.string.contains("word") == true }
                .sorted { $0.frame.minX < $1.frame.minX }
            expect(columns.count) == 2
            guard columns.count == 2 else { return }
            // 마커는 넓은 뒤 단 조각에 있다 — 예약을 다시 풀 자리다.
            let wide = columns[1]
            expect(wide.frame.width).to(beCloseTo(268.37, within: 0.05))
            let object = try XCTUnwrap(Self.objectBlocks(on: page, instanceId: 8).first)
            let reserved = try XCTUnwrap(InlineControlFragmentSupport.reservedMarkerWidth(
                in: try XCTUnwrap(wide.attributedString), controlIndex: 0
            ))
            // 예약 = 그려지는 폭 = 뒤 단의 50% (앞 단의 50%인 67.08pt가 아니다).
            expect(object.frame.width).to(beCloseTo(wide.frame.width / 2, within: 0.05))
            expect(reserved).to(beCloseTo(object.frame.width, within: 0.05))
            expect(object.frame.maxX).to(beLessThanOrEqualTo(wide.frame.maxX + 0.01))
        }
    }

    /// 쪽·단 경계로 나뉜 문단 조각의 줄 프레임 (`HwpParagraphFragmentLines`) — 조각 기준
    /// 되돌리기와, 렌더러가 한 줄로 접을 때의 앵커·정렬 오프셋 (#164).
    final class HwpParagraphFragmentLinesTests: XCTestCase {
        /// 조각 줄은 문자열 범위를 조각 기준으로, 원점 y를 조각 첫 줄 기준 델타로 되돌린다.
        func testFragmentLineFramesRebaseRangesAndOrigins() {
            let lines = [
                HwpLineFrame(
                    origin: CGPoint(x: 0, y: 0), width: 100, baseline: 12,
                    attributedRange: NSRange(location: 0, length: 10)
                ),
                HwpLineFrame(
                    origin: CGPoint(x: 0, y: 16), width: 100, baseline: 12,
                    attributedRange: NSRange(location: 10, length: 10),
                    inlineAnchors: [
                        HwpInlineAnchor(controlIndex: 0, xOffset: 5, ascent: 8, width: 6),
                    ]
                ),
                HwpLineFrame(
                    origin: CGPoint(x: 3, y: 32), width: 100, baseline: 12,
                    attributedRange: NSRange(location: 20, length: 10)
                ),
            ]
            let fragment = HwpParagraphLayout.fragmentLineFrames(
                lines[1...], range: NSRange(location: 10, length: 20)
            )
            expect(fragment.count) == 2
            expect(fragment.map(\.origin.y)) == [0, 16]
            expect(fragment.map(\.origin.x)) == [0, 3]
            expect(fragment.map(\.attributedRange.location)) == [0, 10]
            expect(fragment.map(\.attributedRange.length)) == [10, 10]
            expect(fragment.map(\.baseline)) == [12, 12]
            expect(fragment[0].inlineAnchors.map(\.controlIndex)) == [0]
            let empty = HwpParagraphLayout.fragmentLineFrames(
                [], range: NSRange(location: 0, length: 0)
            )
            expect(empty).to(beEmpty())
        }

        /// 조각이 혼자서는 slight-overflow 한 줄에 들어가면 (문단에서는 다음 줄로 넘어간
        /// 좁은 마커) 렌더러가 한 줄로 그리므로 앵커도 그 한 줄에서 찾는다.
        func testFragmentAnchorLinesCollapseWhenTheRendererDrawsOneLine() throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            var paragraph = HwpSynthetic.paragraphWithInlineControl(
                prefix: String(repeating: "가", count: 20), suffix: ""
            )
            paragraph.ctrlHeaderArray = [
                try InlineControlFragmentSupport.inlineTable(instanceId: 1),
            ]
            let fragment = HwpTextRunBuilder(
                index: index, fontResolver: .testDeterministic, attributeCache: nil
            ).build(paragraph: paragraph)
            let natural = CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(fragment), nil, nil, nil
            ))
            // 자연 폭이 단 폭의 1.03배 — 렌더러의 한 줄 허용치(1.06배) 안이다.
            let columnWidth = natural / 1.03
            let twoLines = [
                HwpLineFrame(
                    origin: .zero, width: columnWidth, baseline: 10,
                    attributedRange: NSRange(location: 0, length: 20)
                ),
                HwpLineFrame(
                    origin: CGPoint(x: 0, y: 16), width: 60, baseline: 10,
                    attributedRange: NSRange(location: 20, length: 1),
                    inlineAnchors: [
                        HwpInlineAnchor(controlIndex: 0, xOffset: 0, ascent: 10, width: 60),
                    ]
                ),
            ]
            let drawn = HwpParagraphLayout.fragmentLineFramesAsDrawn(
                twoLines, fragment: fragment, columnWidth: columnWidth
            )
            expect(drawn.count) == 1
            expect(drawn.first?.attributedRange) == NSRange(location: 0, length: 21)
            expect(drawn.first?.inlineAnchors.map(\.controlIndex)) == [0]
            // 마커는 한 줄의 끝 — 글자 20개 뒤, 표 폭 60pt 앞에 있다.
            expect(drawn.first?.inlineAnchors.first?.xOffset ?? 0)
                .to(beCloseTo(natural - 60, within: 1))
            // 넉넉한 단에서는 (한 줄 접힘이 아니므로) 원래 줄을 그대로 돌려준다.
            expect(HwpParagraphLayout.fragmentLineFramesAsDrawn(
                twoLines, fragment: fragment, columnWidth: natural * 2
            ).count) == 2
        }

        /// 오른쪽 정렬 조각이 한 줄로 접히면 렌더러는 초과분만큼 왼쪽으로 당겨 오른쪽 끝을
        /// 맞춘다 — 앵커 원점 x도 같은 오프셋이어야 표가 단 오른쪽 경계를 넘지 않는다.
        func testCollapsedFragmentAnchorFollowsRightAlignment() throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            var paragraph = HwpSynthetic.paragraphWithInlineControl(
                prefix: String(repeating: "가", count: 20), suffix: ""
            )
            paragraph.ctrlHeaderArray = [
                try InlineControlFragmentSupport.inlineTable(instanceId: 1),
            ]
            let built = HwpTextRunBuilder(
                index: index, fontResolver: .testDeterministic, attributeCache: nil
            ).build(paragraph: paragraph)
            let fragment = NSMutableAttributedString(attributedString: built)
            fragment.addAttribute(
                kCTParagraphStyleAttributeName as NSAttributedString.Key,
                value: HwpParagraphLayout.paragraphStyle(
                    for: InlineControlFragmentSupport.rightAlignedParaShape(),
                    attributedString: built
                ),
                range: NSRange(location: 0, length: fragment.length)
            )
            let natural = CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(fragment), nil, nil, nil
            ))
            let columnWidth = natural / 1.03
            let twoLines = [
                HwpLineFrame(
                    origin: .zero, width: columnWidth, baseline: 10,
                    attributedRange: NSRange(location: 0, length: 20)
                ),
                HwpLineFrame(
                    origin: CGPoint(x: 0, y: 16), width: 60, baseline: 10,
                    attributedRange: NSRange(location: 20, length: 1),
                    inlineAnchors: [
                        HwpInlineAnchor(controlIndex: 0, xOffset: 0, ascent: 10, width: 60),
                    ]
                ),
            ]
            let drawn = HwpParagraphLayout.fragmentLineFramesAsDrawn(
                twoLines, fragment: fragment, columnWidth: columnWidth
            )
            let line = try XCTUnwrap(drawn.first)
            expect(drawn.count) == 1
            // 오른쪽 정렬: 초과분(자연 폭 − 단 폭)만큼 음수 오프셋.
            expect(line.origin.x).to(beCloseTo(columnWidth - natural, within: 0.01))
            let anchor = try XCTUnwrap(line.inlineAnchors.first)
            let marker = try XCTUnwrap(InlineControlFragmentSupport.drawnMarker(
                in: fragment, origin: .zero, lineWidth: columnWidth, controlIndex: 0
            ))
            expect(line.origin.x + anchor.xOffset).to(beCloseTo(marker.x, within: 0.01))
            // 표(60pt)의 오른쪽 끝이 단 폭을 넘지 않는다.
            expect(line.origin.x + anchor.xOffset + 60).to(beLessThanOrEqualTo(columnWidth + 0.01))
        }

        /// 목적 단 폭으로 다시 조판한 조각이 **이미 한 줄**이어도 렌더러의 정렬 오프셋을
        /// 따라야 한다 — 측정의 한 줄 분기가 낸 원점 0을 그대로 두면 오른쪽 정렬 조각의
        /// 앵커가 초과분만큼 오른쪽에 놓여 표가 단 경계를 넘는다 (PR 리뷰).
        func testSingleFrameFragmentAnchorFollowsRightAlignment() throws {
            let index = HwpIndex(from: CoreHwp.HwpFile())
            var paragraph = HwpSynthetic.paragraphWithInlineControl(
                prefix: String(repeating: "가", count: 20), suffix: ""
            )
            paragraph.ctrlHeaderArray = [
                try InlineControlFragmentSupport.inlineTable(instanceId: 1),
            ]
            let shape = InlineControlFragmentSupport.rightAlignedParaShape()
            let built = HwpTextRunBuilder(
                index: index, fontResolver: .testDeterministic, attributeCache: nil
            ).build(paragraph: paragraph)
            let fragment = NSMutableAttributedString(attributedString: built)
            fragment.addAttribute(
                kCTParagraphStyleAttributeName as NSAttributedString.Key,
                value: HwpParagraphLayout.paragraphStyle(for: shape, attributedString: built),
                range: NSRange(location: 0, length: fragment.length)
            )
            let natural = CGFloat(CTLineGetTypographicBounds(
                CTLineCreateWithAttributedString(fragment), nil, nil, nil
            ))
            let columnWidth = natural / 1.03
            // `fragmentAnchorLines`의 비등폭 분기와 같은 재조판 — 한 줄이 나온다.
            let relaid = HwpParagraphLayout().layout(
                attributedString: fragment, paraShape: shape, columnWidth: columnWidth
            ).lines
            expect(relaid.count) == 1
            expect(relaid.first?.origin.x).to(beCloseTo(0, within: 0.01))
            let drawn = HwpParagraphLayout.fragmentLineFramesAsDrawn(
                relaid, fragment: fragment, columnWidth: columnWidth
            )
            let line = try XCTUnwrap(drawn.first)
            expect(drawn.count) == 1
            expect(line.origin.x).to(beCloseTo(columnWidth - natural, within: 0.01))
            let anchor = try XCTUnwrap(line.inlineAnchors.first)
            let marker = try XCTUnwrap(InlineControlFragmentSupport.drawnMarker(
                in: fragment, origin: .zero, lineWidth: columnWidth, controlIndex: 0
            ))
            expect(line.origin.x + anchor.xOffset).to(beCloseTo(marker.x, within: 0.01))
            expect(line.origin.x + anchor.xOffset + 60).to(beLessThanOrEqualTo(columnWidth + 0.01))
            // 넉넉한 단은 접기 술어가 nil이라 한 줄 입력도 그대로 돌려준다.
            expect(HwpParagraphLayout.fragmentLineFramesAsDrawn(
                relaid, fragment: fragment, columnWidth: natural * 2
            ).first?.origin.x).to(beCloseTo(0, within: 0.01))
        }
    }
#endif

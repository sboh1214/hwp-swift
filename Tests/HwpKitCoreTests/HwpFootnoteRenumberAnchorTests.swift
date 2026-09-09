import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 쪽마다 새로 시작하는 각주(표 134 번호 매김 2)에서 조각의 참조 번호를 다시 쓰면
    /// 번호 **폭**이 바뀔 수 있는데, 조각 줄은 다시 쓰기 **전** 문자열로 재어졌다 —
    /// 그 줄로 앵커를 잡으면 마커 뒤의 글자처럼 취급 개체가 옛 x에 남는다 (PR 리뷰).
    ///
    /// 번호 정합(참조와 각주가 같은 번호를 쓰는지)은 `HwpFootnoteFragmentAttributionTests`가
    /// 본다. 여기는 **앵커 정합**만 본다.
    final class HwpFootnoteRenumberAnchorTests: XCTestCase {
        /// 세 줄이 두 쪽으로 갈리고, 뒤 조각의 줄이 각주 참조와 표 마커를 **나란히** 갖는
        /// 문단. 표는 참조 **뒤**에 있어 번호 폭이 바뀌면 x가 함께 움직여야 한다.
        private func splitHost() throws -> CoreHwp.HwpParagraph {
            var host = try HwpSynthetic.splitParagraphWithMixedMarkers(
                lines: [
                    (characters: 5, markers: [17]),
                    (characters: 5, markers: []),
                    (characters: 5, markers: [17, 11]),
                ],
                segments: [
                    (location: 2720, height: 1500, textStart: 0),
                    (location: 4820, height: 1500, textStart: 6),
                    // location이 줄어드는 지점이 한글의 페이지 절단점 (run 1)
                    (location: 2720, height: 1500, textStart: 12),
                ]
            )
            host.ctrlHeaderArray = [
                Self.footnote("앞 조각 각주"),
                Self.footnote("뒤 조각 각주"),
                try Self.inlineTable(instanceId: 7),
            ]
            return host
        }

        private static func footnote(_ text: String) -> CoreHwp.HwpCtrlId {
            .footnote(HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [HwpSynthetic.noteParagraph(
                    " \(text)",
                    autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                )]
            ))
        }

        private static func inlineTable(instanceId: UInt32) throws -> CoreHwp.HwpCtrlId {
            try InlineControlFragmentSupport.inlineTable(instanceId: instanceId)
        }

        /// 절대 캐시 모드 감지(첫 loc > 0인 캐시 문단이 다수)를 만족시키는 문서.
        private func paginate(
            _ host: CoreHwp.HwpParagraph,
            footnoteNumberingMode: UInt32,
            footnoteStartingNumber: UInt16
        ) throws -> HwpPaginator {
            let tail = try (0 ..< 2).map { index in
                try HwpSynthetic.lineSegParagraph(
                    "뒤 문단 \(index)",
                    segments: [(location: Int32(4820 + index * 2100), height: 1500)]
                )
            }
            let section = HwpSynthetic.section(
                firstParagraphControls: [.section(HwpSynthetic.sectionDef(
                    footnoteNumberingMode: footnoteNumberingMode,
                    footnoteStartingNumber: footnoteStartingNumber
                ))],
                bodyParagraphs: [host] + tail
            )
            return HwpPaginator(
                sections: [section],
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
        }

        /// 뒤 쪽에 놓인 (본문 문단 조각, 표) 짝.
        private func secondPagePlacement(
            mode: UInt32,
            startingNumber: UInt16
        ) async throws -> (fragment: AnyHwpBlock, table: AnyHwpBlock) {
            let paginator = try paginate(
                try splitHost(),
                footnoteNumberingMode: mode,
                footnoteStartingNumber: startingNumber
            )
            _ = try await paginator.page(at: 0)
            let rendered = try await paginator.page(at: 1)
            let page = try XCTUnwrap(rendered)
            let fragment = try XCTUnwrap(page.blocks.first {
                $0.kind == .text && $0.source?.sectionIndex == 0 && $0.source?.paragraphIndex == 1
            })
            let table = try XCTUnwrap(page.blocks.first {
                $0.kind == .table && $0.source?.controlInstanceId == 7
            })
            return (fragment, table)
        }

        /// 번호가 3자에서 2자로 줄어든 조각에서도 표는 **그려진 마커 자리**에 놓인다.
        /// 옛 번호로 잰 줄을 그대로 쓰면 표가 줄어든 한 자 폭만큼 오른쪽에 남는다.
        func testRenumberedFragmentAnchorsFollowTheDrawnMarker() async throws {
            let placed = try await secondPagePlacement(mode: 2, startingNumber: 9)
            let text = try XCTUnwrap(placed.fragment.attributedString)
            // 전제: 이 조각의 번호는 실제로 다시 쓰였다 (10) → 9)).
            expect(text.string).to(contain("9)"))
            expect(text.string).toNot(contain("10)"))

            let drawn = try XCTUnwrap(InlineControlFragmentSupport.drawnMarker(
                in: text,
                origin: placed.fragment.frame.origin,
                lineWidth: placed.fragment.frame.width,
                controlIndex: 2
            ))
            expect(placed.table.frame.minX).to(beCloseTo(drawn.x, within: 0.5))
            expect(placed.table.frame.minY)
                .to(beGreaterThanOrEqualTo(placed.fragment.frame.minY - 0.01))
            expect(placed.table.frame.maxY)
                .to(beLessThanOrEqualTo(placed.fragment.frame.maxY + 0.01))
        }

        /// 대조: 번호가 이어지는 문서(모드 0)는 재기록이 항등이라 조각을 다시 조판하지
        /// 않는다 — 같은 픽스처의 표 좌표가 재조판 갈래와 같아야 렌더 불변이 성립한다.
        func testContinuousNumberingKeepsTheSameAnchor() async throws {
            let renumbered = try await secondPagePlacement(mode: 2, startingNumber: 9)
            let untouched = try await secondPagePlacement(mode: 0, startingNumber: 9)
            let text = try XCTUnwrap(untouched.fragment.attributedString)
            // 모드 0은 이어지는 번호라 뒤 조각이 10)을 그대로 쓴다.
            expect(text.string).to(contain("10)"))
            let drawn = try XCTUnwrap(InlineControlFragmentSupport.drawnMarker(
                in: text,
                origin: untouched.fragment.frame.origin,
                lineWidth: untouched.fragment.frame.width,
                controlIndex: 2
            ))
            expect(untouched.table.frame.minX).to(beCloseTo(drawn.x, within: 0.5))
            // 번호 한 자가 더 길므로 표는 재매김된 쪽보다 오른쪽에 있다 — 두 갈래가
            // 같은 좌표를 내면 픽스처가 폭 변화를 태우지 못하고 있다는 뜻이다.
            expect(untouched.table.frame.minX) > renumbered.table.frame.minX + 0.5
        }
    }
#endif

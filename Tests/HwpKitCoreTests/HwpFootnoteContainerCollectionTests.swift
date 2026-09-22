import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 컨테이너 (글상자·도형·미주) 안 각주의 수집 규약 (#95). 배치를 미루는 것과
    /// 번호를 미루는 것은 다르고, 번호의 소유자는 **그 번호가 읽힐 쪽**이다 —
    /// 연속 번호에서는 문서 순서, 쪽마다 새로 시작에서는 그려질 쪽.
    ///
    /// 조각 귀속 자체 (실제 paginator로 본 페이지 단위 동작) 는
    /// `HwpFootnoteFragmentAttributionTests` 몫이고, 여기서는 수집기 규약만 잠근다.
    final class HwpFootnoteContainerCollectionTests: XCTestCase {
        /// 컨테이너 (글상자·도형) 는 `appendControlBlocks`가 모든 조각을 놓은 **뒤**
        /// 방출해 마지막 조각 페이지에 그려진다. 그 안의 각주를 앞 조각에서 걷으면
        /// 각주와 그것을 그리는 컨테이너가 갈린다 — 앞 조각에서는 내려가지 않고,
        /// 마지막 조각에서는 서수 범위 **밖**이어도 내려가야 한다 (안 그러면 유실).
        func testNestedNotesWaitForTheFragmentThatDrawsTheirContainer() {
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            var host = CoreHwp.HwpParagraph()
            host.ctrlHeaderArray = [
                .header(HwpSynthetic.listControl(ctrlId: .header, paragraphs: [])),
            ]
            var nested = CoreHwp.HwpParagraph()
            nested.ctrlHeaderArray = [
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 컨테이너 안 각주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            // 컨테이너만 자식을 갖는다 — 모든 컨트롤에 돌려주면 각주 리스트가
            // 자기 자신을 자식으로 받아 깊이 상한까지 재귀한다.
            let children: HwpFootnoteCoordinator.ChildParagraphs = { ctrl in
                if case .header = ctrl {
                    return [(nested, .textbox)]
                }
                return []
            }
            let environment = HwpFootnoteCoordinator.Environment(
                contentWidth: 400, footnoteShape: nil
            )

            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 0 ..< 1,
                collectsNested: false,
                environment: environment,
                childParagraphs: children
            )
            expect(coordinator.pendingFootnotes).to(beEmpty())
            // 미룬 각주는 이 페이지 몫이 아니므로 예약도 하지 않는다 — 예약이
            // 늘면 effectiveContentHeight가 줄어 본문 절단점이 흔들린다.
            expect(coordinator.footnoteReservedHeight) == 0

            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 1 ..< 1,
                collectsNested: true,
                environment: environment,
                childParagraphs: children
            )
            expect(coordinator.pendingFootnotes.count) == 1
            expect(coordinator.footnoteReservedHeight) > 0
            // 버퍼를 풀고 **또** 걷지 않는다 — 그러면 같은 각주가 두 번 실리고
            // 번호도 하나 더 소비된다.
            expect(coordinator.footnoteCounter) == 1
        }

        /// 번호는 **문서 순서**다 — 컨테이너 안 각주가 그 뒤의 직접 각주보다 앞선다.
        /// 배치를 미루면서 번호까지 미루면 뒤의 직접 각주가 먼저 카운터를 가져가
        /// 둘이 뒤바뀐다 (#95 리뷰 r3708636335).
        func testDeferredContainerNotesKeepTheirDocumentOrderNumbers() {
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            var host = CoreHwp.HwpParagraph()
            host.ctrlHeaderArray = [
                .header(HwpSynthetic.listControl(ctrlId: .header, paragraphs: [])),
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 뒤따르는 직접 각주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            var nested = CoreHwp.HwpParagraph()
            nested.ctrlHeaderArray = [
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 컨테이너 안 각주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            let children: HwpFootnoteCoordinator.ChildParagraphs = { ctrl in
                if case .header = ctrl {
                    return [(nested, .textbox)]
                }
                return []
            }
            let environment = HwpFootnoteCoordinator.Environment(
                contentWidth: 400, footnoteShape: nil
            )

            // 앞 조각: 컨테이너(서수 0)와 직접 각주(서수 1)가 같은 조각에 있다
            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 0 ..< 2,
                collectsNested: false,
                environment: environment,
                childParagraphs: children
            )
            expect(coordinator.pendingFootnotes.count) == 1
            let directNumber = coordinator.pendingFootnotes[0].number

            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 2 ..< 2,
                collectsNested: true,
                environment: environment,
                childParagraphs: children
            )
            expect(coordinator.pendingFootnotes.count) == 2
            let nestedNumber = coordinator.pendingFootnotes[1].number

            expect(nestedNumber) == 0
            expect(directNumber) == 1
        }

        /// "쪽마다 새로 시작" (표 134 numberingMode 2) 에서는 번호가 **그려질 쪽**의
        /// 함수라 앞 조각에서 받아 둘 수 없다 — run 사이 `cacheCurrentPage`가 카운터를
        /// 시작 번호로 되돌리므로, 미리 받은 번호가 그 쪽 첫 직접 각주와 같아진다
        /// (#95 리뷰 r3709468093).
        func testPerPageNumberingLetsTheFinalFragmentNumberContainerNotes() {
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            coordinator.footnoteCounter = 1
            var host = CoreHwp.HwpParagraph()
            host.ctrlHeaderArray = [
                .header(HwpSynthetic.listControl(ctrlId: .header, paragraphs: [])),
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 마지막 조각의 직접 각주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            var nested = CoreHwp.HwpParagraph()
            nested.ctrlHeaderArray = [
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 컨테이너 안 각주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            let children: HwpFootnoteCoordinator.ChildParagraphs = { ctrl in
                if case .header = ctrl {
                    return [(nested, .textbox)]
                }
                return []
            }
            let environment = HwpFootnoteCoordinator.Environment(
                contentWidth: 400,
                footnoteShape: HwpSynthetic.sectionDef(footnoteNumberingMode: 2).footNoteShape
            )

            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 0 ..< 1,
                collectsNested: false,
                environment: environment,
                childParagraphs: children
            )
            // cacheCurrentPage와 같은 일: 앞 쪽을 확정하고 카운터를 시작 번호로 되돌린다
            coordinator.pendingFootnotes.removeAll()
            coordinator.footnoteCounter = 1

            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 1 ..< 2,
                collectsNested: true,
                environment: environment,
                childParagraphs: children
            )
            // 이 쪽 카운터에서 나온 번호라 겹치지 않는다 — 컨테이너(서수 0)가 먼저다
            expect(coordinator.pendingFootnotes.map(\.number)) == [1, 2]
        }

        /// 각주는 **이 조각이 곧바로 배치**하므로 그 안쪽 노트도 같은 조각이 걷는다
        /// — 미루면 참조와 갈리고 번호 순서가 밀린다 (#95 리뷰). 마지막 조각이 또
        /// 걷어서도 안 된다 (같은 노트를 두 번 셈).
        func testNotesInsideACollectedFootnoteAreCollectedWithIt() {
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            var host = CoreHwp.HwpParagraph()
            host.ctrlHeaderArray = [
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 바깥 각주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            // 각주 문단 **안**의 노트 — 미주로 두어 스텁 재귀가 멈추게 한다
            var inner = CoreHwp.HwpParagraph()
            inner.ctrlHeaderArray = [
                .endnote(HwpSynthetic.listControl(
                    ctrlId: .endnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 각주 안 미주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            let children: HwpFootnoteCoordinator.ChildParagraphs = { ctrl in
                if case .footnote = ctrl {
                    return [(inner, .footnote)]
                }
                return []
            }
            let environment = HwpFootnoteCoordinator.Environment(
                contentWidth: 400, footnoteShape: nil
            )

            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 0 ..< 1,
                collectsNested: false,
                environment: environment,
                childParagraphs: children
            )
            expect(coordinator.pendingFootnotes.count) == 1
            expect(coordinator.pendingEndnotes.count) == 1

            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 1 ..< 1,
                collectsNested: true,
                environment: environment,
                childParagraphs: children
            )
            expect(coordinator.pendingFootnotes.count) == 1
            expect(coordinator.pendingEndnotes.count) == 1
        }

        /// 미주는 문서·구역 끝에서 흐름 배치되므로 (`placeFlow`) 이 조각이 그리지
        /// 않는다 — 안쪽 각주를 지금 걷으면 참조는 문서 끝에, 각주는 본문 쪽에
        /// 남는다. 글상자·도형과 같이 마지막 조각으로 미룬다 (#95 리뷰).
        func testEndnoteDescendantsWaitForTheFinalFragment() {
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()),
                fontResolver: .testDeterministic
            )
            var host = CoreHwp.HwpParagraph()
            host.ctrlHeaderArray = [
                .endnote(HwpSynthetic.listControl(
                    ctrlId: .endnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 미주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            var inner = CoreHwp.HwpParagraph()
            inner.ctrlHeaderArray = [
                .footnote(HwpSynthetic.listControl(
                    ctrlId: .footnote,
                    paragraphs: [HwpSynthetic.noteParagraph(
                        " 미주 안 각주",
                        autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                    )]
                )),
            ]
            let children: HwpFootnoteCoordinator.ChildParagraphs = { ctrl in
                if case .endnote = ctrl {
                    return [(inner, .footnote)]
                }
                return []
            }
            let environment = HwpFootnoteCoordinator.Environment(
                contentWidth: 400, footnoteShape: nil
            )

            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 0 ..< 1,
                collectsNested: false,
                environment: environment,
                childParagraphs: children
            )
            expect(coordinator.pendingEndnotes.count) == 1
            expect(coordinator.pendingFootnotes).to(beEmpty())

            coordinator.collectFootnotes(
                from: host,
                includeTableCells: false,
                ordinals: 1 ..< 1,
                collectsNested: true,
                environment: environment,
                childParagraphs: children
            )
            expect(coordinator.pendingFootnotes.count) == 1
            expect(coordinator.pendingEndnotes.count) == 1
        }
    }
#endif

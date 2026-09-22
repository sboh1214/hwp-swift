import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 흐름 분할 조각의 각주 **예약**(`anticipatedFootnoteHeight(ordinals:collectsNested:)`·증분
    /// 커서)이 수집(`collectFootnotes`)과 같은 번호·높이를 내는지 (#207 PR 리뷰). 조각 귀속과
    /// 수집 규약은 `HwpFlowFragmentFootnoteTests`·`HwpFootnoteContainerCollectionTests` 몫이다.
    final class HwpFootnoteFragmentReservationTests: XCTestCase {
        /// 최종 조각의 예약은 앞 조각이 미룬 컨테이너 안 각주를 **저장된 번호**로 잰다 — 현재
        /// 카운터로 다시 매기면(`9)` → `10)`) 라벨 폭이 달라 줄바꿈 경계에서 예약이 배치보다 한 줄
        /// 크고, 들어가는 본문이 다음 쪽으로 밀린다 (#207 PR 리뷰). 각주 본문 길이를 훑어 예약 ==
        /// 실제 예약을 잠근다.
        func testFinalFragmentPreflightMeasuresDeferredNotesWithTheirNumbers() {
            for length in 1 ... 40 {
                var coordinator = HwpFootnoteCoordinator(
                    index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
                )
                coordinator.footnoteCounter = 9
                var host = CoreHwp.HwpParagraph()
                host.ctrlHeaderArray = [
                    .header(HwpSynthetic.listControl(ctrlId: .header, paragraphs: [])),
                    .footnote(HwpSynthetic.listControl(
                        ctrlId: .footnote,
                        paragraphs: [HwpSynthetic.noteParagraph(
                            " 뒤따르는 직접 각주 본문 글자들",
                            autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                        )]
                    )),
                ]
                var nested = CoreHwp.HwpParagraph()
                nested.ctrlHeaderArray = [
                    .footnote(HwpSynthetic.listControl(
                        ctrlId: .footnote,
                        paragraphs: [HwpSynthetic.noteParagraph(
                            " " + String(repeating: "가", count: length),
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
                    contentWidth: 100, footnoteShape: nil
                )
                coordinator.collectFootnotes(
                    from: host, includeTableCells: false, ordinals: 0 ..< 1, collectsNested: false,
                    environment: environment, childParagraphs: children
                )
                let before = coordinator.footnoteReservedHeight
                let predicted = coordinator.anticipatedFootnoteHeight(
                    for: host, environment: environment, childParagraphs: children,
                    ordinals: 1 ..< 2, collectsNested: true
                )
                coordinator.collectFootnotes(
                    from: host, includeTableCells: false, ordinals: 1 ..< 2, collectsNested: true,
                    environment: environment, childParagraphs: children
                )
                expect(predicted).to(
                    beCloseTo(coordinator.footnoteReservedHeight - before, within: 0.01),
                    description: "각주 본문 \(length)자"
                )
                expect(coordinator.pendingFootnotes.map(\.number)) == [9, 10]
            }
        }

        /// 비최종 조각 예약의 번호 미리보기는 컨테이너 안 각주의 **자손 각주**까지 센다 — 수집은
        /// 각주 안 각주도 번호를 소비하므로(`walkChildren`), 자신만 세면 그 뒤 직접 각주가 한 번호
        /// 앞선 라벨로 재어진다 (PR 리뷰 2: 실제 `10)`을 `9)`로). 직접 각주 본문 길이를 훑어
        /// 예약 == 실제 예약을 잠근다.
        func testNonFinalFragmentPreflightCountsDescendantNotesOfNestedNotes() {
            for length in 1 ... 40 {
                var coordinator = HwpFootnoteCoordinator(
                    index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
                )
                coordinator.footnoteCounter = 8
                var innermost = CoreHwp.HwpParagraph()
                innermost.ctrlHeaderArray = [
                    .footnote(HwpSynthetic.listControl(
                        ctrlId: .footnote,
                        paragraphs: [HwpSynthetic.noteParagraph(
                            " 각주 안 각주",
                            autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                        )]
                    )),
                ]
                var nested = CoreHwp.HwpParagraph()
                nested.ctrlHeaderArray = [
                    .footnote(HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [innermost])),
                ]
                var host = CoreHwp.HwpParagraph()
                host.ctrlHeaderArray = [
                    .header(HwpSynthetic.listControl(ctrlId: .header, paragraphs: [])),
                    .footnote(HwpSynthetic.listControl(
                        ctrlId: .footnote,
                        paragraphs: [HwpSynthetic.noteParagraph(
                            " " + String(repeating: "가", count: length),
                            autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                        )]
                    )),
                ]
                let children: HwpFootnoteCoordinator.ChildParagraphs = { ctrl in
                    switch ctrl {
                    case .header:
                        [(nested, .textbox)]
                    case let .footnote(list):
                        list.listArray.flatMap(\.paragraphArray).map { ($0, .footnote) }
                    default:
                        []
                    }
                }
                let environment = HwpFootnoteCoordinator.Environment(
                    contentWidth: 100, footnoteShape: nil
                )
                let predicted = coordinator.anticipatedFootnoteHeight(
                    for: host, environment: environment, childParagraphs: children,
                    ordinals: 0 ..< 2, collectsNested: false
                )
                coordinator.collectFootnotes(
                    from: host, includeTableCells: false, ordinals: 0 ..< 2, collectsNested: false,
                    environment: environment, childParagraphs: children
                )
                expect(predicted).to(
                    beCloseTo(coordinator.footnoteReservedHeight, within: 0.01),
                    description: "직접 각주 본문 \(length)자"
                )
                // 컨테이너 안 각주 8·9(미룸)에 이어 직접 각주는 10이다.
                expect(coordinator.pendingFootnotes.map(\.number)) == [10]
            }
        }

        /// 비최종 조각 예약의 증분 커서(`extendFragmentReservation`)는 후보 줄마다 늘어나는 범위를
        /// 앞 후보의 누적 상태에서 이어 재어 한 번에 잰 값과 같다 (PR 리뷰 2: 마커 줄 N개에
        /// N(N+1)/2 순회를 피한다).
        func testIncrementalFragmentReservationMatchesTheOneShotPreflight() {
            var host = CoreHwp.HwpParagraph()
            host.ctrlHeaderArray = (0 ..< 12).map { index in
                index % 3 == 2
                    ? .header(HwpSynthetic.listControl(ctrlId: .header, paragraphs: []))
                    : .footnote(HwpSynthetic.listControl(
                        ctrlId: .footnote,
                        paragraphs: [HwpSynthetic.noteParagraph(
                            " 각주 \(index) " + String(repeating: "가", count: index * 3),
                            autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
                        )]
                    ))
            }
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
                contentWidth: 120, footnoteShape: nil
            )
            var coordinator = HwpFootnoteCoordinator(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic
            )
            coordinator.footnoteCounter = 3
            var cursor = coordinator.fragmentReservationCursor(from: 2)
            for upperBound in 2 ... 12 {
                let incremental = coordinator.extendFragmentReservation(
                    &cursor, for: host, through: upperBound, environment: environment,
                    childParagraphs: children
                )
                let oneShot = coordinator.anticipatedFootnoteHeight(
                    for: host, environment: environment, childParagraphs: children,
                    ordinals: 2 ..< upperBound, collectsNested: false
                )
                expect(incremental).to(beCloseTo(oneShot, within: 0.01), description: "2..<\(upperBound)")
            }
            expect(cursor.upperBound) == 12
        }
    }
#endif

import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 합성 조립·페이지네이션 헬퍼 — 클래스 본문이 SwiftLint type_body_length
    /// 상한(400줄)에 닿아 갈라 뒀다.
    /// 각주 이어짐 (#165) PR 리뷰가 잡은 경계·개체·식별·모양 결함의 재현 — 전부 수정 전에
    /// 실패했고 실물 코퍼스(헌법주석)엔 없는 형상이라 합성으로만 잠근다. 조립 헬퍼는
    /// `FootnoteContinuationSupport`, 이어짐 규칙 자체는 `HwpFootnoteContinuationTests`.
    final class HwpFootnoteContinuationReviewTests: XCTestCase {
        private typealias Support = FootnoteContinuationSupport

        /// stale 캐시(캐시 줄 높이 < 글자 크기) 문단이 쪽의 마지막 본문이면 그 블록은 CT
        /// 높이로 커지는데, 커진 몫을 마지막 줄의 줄 간격으로 잘못 기록하면 본문 하한이
        /// 캐시 잉크 아래로 되돌아가 각주 구분선이 커진 글자 위에 그어진다 (#165 리뷰).
        func testStaleCacheGrowthIsNotSubtractedFromTheBodyBottom() async throws {
            // 세 줄, 캐시 줄 높이 5pt(10pt 글자보다 작다 → stale) — CT는 48pt로 다시 조판된다.
            var host = try HwpSynthetic.splitParagraphWithMixedMarkers(
                lines: [
                    (characters: 5, markers: []),
                    (characters: 5, markers: []),
                    (characters: 5, markers: [17]),
                ],
                segments: [
                    (location: 60000, height: 500, textStart: 0),
                    (location: 61100, height: 500, textStart: 6),
                    (location: 62200, height: 500, textStart: 12),
                ]
            )
            // 스택은 바닥 정렬이라 잘못된 하한이 드러나려면 각주가 그 자리를 다 채워야
            // 한다 — 여덟 줄(91.04pt)은 캐시 잉크 기준 자리(101pt)엔 들어가고 CT 기준
            // 자리(80pt)엔 안 들어간다.
            let lines = (1 ... 8).map { "줄 \($0)" }
            host.ctrlHeaderArray = [.footnote(HwpSynthetic.listControl(
                ctrlId: .footnote,
                paragraphs: [try Support.note(
                    lines: lines, locations: (0 ..< 8).map { Int32($0 * 1172) }
                )]
            ))]
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))
            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)
            let page = try XCTUnwrap(firstPage)
            // 구역 템플릿의 빈 첫 문단이 아니라 **가장 아래** 본문 블록(host)이다.
            let body = try XCTUnwrap(
                page.blocks.filter { $0.kind == .text && $0.role == .body }
                    .max { $0.frame.maxY < $1.frame.maxY }
            )

            // 블록은 CT 높이(3줄 × 16pt)로 커졌고, 이 쪽에 실린 각주의 구분선은 그 아래여야
            // 한다 (자리가 없으면 다음 쪽으로 옮겨지는 것이 옳다).
            expect(body.frame.height).to(beCloseTo(48, within: 1))
            for note in Support.footnoteBlocks(on: page) {
                expect(note.separatorLine.minY) >= body.frame.maxY - 0.01
            }
            expect(Support.footnoteBlocks(on: firstPage).count
                + Support.footnoteBlocks(on: secondPage).count) == 1
        }

        /// 쪽 끝에서 나뉜 각주의 **앞 조각**은 이어짐 표식을 단다 (#165 리뷰). 컨테이너
        /// 문단은 위치 열쇠가 없어 복사가 이 표식으로 조각을 잇고, 양쪽 정렬은 이 표식으로
        /// 조각 끝 줄이 문단의 마지막 줄이 아님을 안다. 이어지는 조각(문단 끝)엔 없다.
        func testSplitHeadCarriesTheContinuedFragmentMarker() async throws {
            let note = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            let host = try Support.host(at: Support.hostLocation(leaving: 40), notes: [[note]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))
            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)
            let head = try XCTUnwrap(Support.footnoteBlocks(on: firstPage).first)
            let tail = try XCTUnwrap(Support.footnoteBlocks(on: secondPage).first)

            expect(Self.isContinued(head)) == true
            expect(Self.isContinued(tail)) == false
        }

        /// 캐시 분할 지점이 뒤에 있어도 **앞 조각 전체**가 들어가야 나눈다 (#165 리뷰).
        /// 첫 줄만 보고 나누면 분할 지점까지의 줄이 전부 방출돼 스택이 자리를 넘고, 바닥
        /// 정렬이 그 스택을 본문 위로 올린다 — 캐시가 저작된 자리보다 우리 본문 하한이
        /// 낮을 때(stale 보정 등) 생긴다. 안 들어가면 통째로 다음 쪽이다.
        func testHeadMustFitWhollyBeforeSplitting() async throws {
            // 분할 지점이 셋째 줄 뒤 — 앞 조각 32.44pt는 15pt 자리에 못 들어간다.
            let note = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            let host = try Support.host(at: Support.hostLocation(leaving: 15), notes: [[note]])
            let paginator = Support.paginate([host] + (try Support.nextPageBody()))
            let firstPage = try await paginator.page(at: 0)
            let secondPage = try await paginator.page(at: 1)
            let page = try XCTUnwrap(firstPage)
            let body = try XCTUnwrap(
                page.blocks.filter { $0.kind == .text && $0.role == .body }
                    .max { $0.frame.maxY < $1.frame.maxY }
            )
            for placed in Support.footnoteBlocks(on: page) {
                expect(placed.separatorLine.minY) >= body.frame.maxY - 0.01
            }
            expect(Support.footnoteBlocks(on: firstPage).count
                + Support.footnoteBlocks(on: secondPage).count) >= 1
            expect(Support.text(try XCTUnwrap(Support.footnoteBlocks(on: secondPage).first)))
                .to(contain("첫째 줄"))
        }

        /// 본문 하한은 프레임이 아니라 **그려지는 범위**다 (#165 리뷰). 표 안의 글 앞으로
        /// 개체는 행을 키우지 않고 표 아래로 그려지므로, 프레임만 보면 각주 스택이 그 개체
        /// 위에 놓인다 — 겹침 가드(`FixtureFootnoteOverlapTests`)와 같은 정의를 쓴다.
        func testBodyBottomIncludesPaintedDescendantsBelowTheFrame() async throws {
            // 앞 조각(3줄, 32.44pt)은 개체 아래 자리(≈46pt)에 들어가고, 전체(102.76pt)는
            // 표 프레임 기준 자리(≈216pt)엔 들어가지만 개체 아래엔 안 들어간다.
            let note = try Support.note(
                lines: (1 ... 9).map { "줄 \($0)" },
                locations: [0, 1172, 2344, 0, 1172, 2344, 3516, 4688, 5860]
            )
            let noteHost = try Support.host(at: 40000, notes: [[note]])
            var cell = try HwpSynthetic.textParagraph("셀")
            cell.ctrlHeaderArray = [.genShapeObject(HwpSynthetic.floatingShapeObject(
                width: 20000, height: 20000, textWrap: .inFrontOfText
            ))]
            var tableHost = try HwpSynthetic.lineSegParagraph(
                "", segments: [(location: 48268, height: 1000)]
            )
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 11)]
            tableHost.paraText = paraText
            tableHost.ctrlHeaderArray = [.table(HwpSynthetic.placed(
                HwpSynthetic.table(
                    cellWidth: 20000, rowHeights: [3000], cellParagraphs: [[[cell]]]
                ),
                treatAsChar: true
            ))]
            let paginator = Support.paginate([noteHost, tableHost] + (try Support.nextPageBody()))
            let firstPage = try await paginator.page(at: 0)
            let page = try XCTUnwrap(firstPage)
            let tableBlock = try XCTUnwrap(page.blocks.first { $0.kind == .table && $0.role == .body })
            guard case let .table(table) = tableBlock.payload else {
                return fail("표 블록의 payload가 없다")
            }
            var paintedBottom = tableBlock.frame.maxY
            HwpBlockContentWalker.walkTable(
                table, origin: tableBlock.frame.origin,
                onParagraphText: { _, _, _ in },
                onCellShape: { shape, rect in
                    paintedBottom = max(paintedBottom, shape.paintedRect.offsetBy(
                        dx: rect.minX - shape.rect.minX, dy: rect.minY - shape.rect.minY
                    ).maxY)
                }
            )
            // 개체가 표 프레임 아래로 그려진다는 전제부터 확인한다.
            expect(paintedBottom) > tableBlock.frame.maxY + 100
            let placed = Support.footnoteBlocks(on: page)
            expect(placed.count) == 1
            for block in placed {
                expect(block.separatorLine.minY) >= paintedBottom - 0.01
            }
        }

        private static func isContinued(_ block: HwpFootnoteBlock) -> Bool {
            guard let attributed = block.paragraphs.first?.attributedString, attributed.length > 0
            else { return false }
            return attributed.attribute(
                HwpAttributedStringKey.continuedParagraphFragment,
                at: attributed.length - 1, effectiveRange: nil
            ) != nil
        }

        /// 폭이 다른 구역으로 이월돼도 **앞 쪽이 소비한 문자 경계**가 보존돼야 한다
        /// (#165 리뷰). 이어지는 조각은 새 쪽의 폭으로 문단을 다시 조판하므로 줄 나눔이
        /// 달라진다 — 캐시 줄 인덱스를 CT 줄 수에 비례 환산한 경계는 앞 쪽이 실제로 그린
        /// 마지막 글자와 다른 자리를 가리켜 글자가 통째로 사라지거나 겹친다.
        func testContinuationKeepsConsumedTextAcrossAWidthChange() throws {
            let words = (1 ... 60).map { "word\($0)" }.joined(separator: " ")
            var paragraph = HwpSynthetic.noteParagraph(
                " " + words,
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0, 1172, 2344, 0, 1172, 2344]))
            )
            let input = HwpFootnoteLayout.Input(paragraph: paragraph, number: 1)
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let wide = Support.geometry(contentWidth: 451)
            let narrow = Support.geometry(contentWidth: 200)

            // 통째 배치(빈 쪽)의 문자열이 이 각주의 전체 텍스트다 — 폭과 무관하다.
            let whole = layout.place(
                footnotes: [input], onPage: wide, index: index, limitsAreaToHalfContent: false
            )
            let full = Support.text(try XCTUnwrap(whole.blocks.first))
            // 앞 세 줄(44.16pt)은 들어가고 전체(91.04pt)는 안 들어가는 자리에서 나눈다.
            let split = layout.place(
                footnotes: [input], onPage: wide, index: index,
                limitsAreaToHalfContent: false, bodyBottom: wide.contentFrame.maxY - 64.2
            )
            let head = Support.text(try XCTUnwrap(split.blocks.first))
            expect(split.overflow.count) == 1
            // 이월분은 **좁은** 쪽에서 다시 조판된다.
            let carried = layout.place(
                footnotes: split.overflow, onPage: narrow, index: index,
                limitsAreaToHalfContent: false
            )
            let tail = Support.text(try XCTUnwrap(carried.blocks.first))

            expect(full.hasPrefix(head)) == true
            expect(full.hasSuffix(tail)) == true
            expect(head.count + tail.count) == full.count
        }

        /// 개체를 담은 각주를 통째로 배치할 때 블록이 그 개체를 담아야 한다 (#165 리뷰).
        /// 쪽에 걸친 캐시(비단조)의 쪽 몫 합은 한글이 **두 쪽에 나눠** 그린 높이인데,
        /// 개체를 담은 각주는 나누지 않고 한 쪽에 통째로 그리므로 그 합으로는 CT 좌표로
        /// 수집한 개체를 담지 못해 다음 각주와 겹친다.
        func testWholeNoteWithAnObjectKeepsAHeightThatContainsIt() throws {
            var paragraph = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 18)]
                + " 첫째 줄\n둘째 줄\n셋째 줄\n넷째 줄 ".utf16
                .map { CoreHwp.HwpChar(type: .char, value: $0) }
                + [CoreHwp.HwpChar(type: .extended, value: 11)]
            paragraph.paraText = paraText
            paragraph.ctrlHeaderArray = [
                HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")"),
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 2000, height: 3000)),
            ]
            // 세로 위치가 되돌아가는 캐시 — 한글이 두 쪽에 나눠 그린 각주다.
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0, 1172, 0, 1172]))
            )
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let placement = layout.place(
                footnotes: [HwpFootnoteLayout.Input(paragraph: paragraph, number: 1)],
                onPage: Support.geometry(contentWidth: 451),
                index: HwpIndex(from: CoreHwp.HwpFile()),
                limitsAreaToHalfContent: false
            )
            let block = try XCTUnwrap(placement.blocks.first)
            let objectBottom = block.shapes.map(\.rect.maxY).max() ?? 0
            expect(objectBottom) > 0
            expect(block.frame.height) >= objectBottom - 0.01
        }

        /// 쪽마다 번호를 새로 시작하면 (표 134 모드 2) 이월된 각주와 새 각주가 **같은 표시
        /// 번호**를 갖는다 (#165 리뷰). 번호로 그룹을 나누면 둘이 한 각주로 합쳐져 사이
        /// 여백이 사라지고, 앞 각주의 마지막 줄 간격까지 높이에 남는다.
        func testCarriedAndNewNoteSharingADisplayNumberStayDistinct() async throws {
            let split = try Support.note(lines: ["첫째 줄", "둘째 줄"], locations: [0, 0])
            let fresh = try Support.note(lines: ["새 각주"], locations: [0])
            let host = try Support.host(at: Support.hostLocation(leaving: 15), notes: [[split]])
            let nextHost = try Support.host(at: 2720, notes: [[fresh]])
            let paginator = Support.paginate([host, nextHost], footnoteNumberingMode: 2)

            let second = try await paginator.page(at: 1)
            let blocks = Support.footnoteBlocks(on: second)
            expect(blocks.count) == 2
            expect(blocks.map(\.number)) == [1, 1]
            // 이어지는 조각은 그 각주의 끝이다 — 마지막 줄의 줄 간격을 세지 않는다.
            expect(blocks[0].frame.height).to(beCloseTo(Support.box, within: 0.01))
            // 서로 다른 각주 사이에는 여백이 들어간다.
            expect(blocks[1].frame.minY - blocks[0].frame.maxY).to(beCloseTo(
                HwpRenderTuning.Footnote.dividerDefaultSpacingBetweenNotes, within: 0.01
            ))
        }

        /// 구역이 바뀌어 **번호 장식**이 달라져도 소비한 문자 경계가 보존돼야 한다
        /// (#165 리뷰). 이어지는 조각은 그 쪽 구역의 각주 모양으로 문자열을 다시 만드는데,
        /// 라벨 길이가 달라지면 본문 글자 위치가 통째로 밀려 앞 쪽이 그린 마지막 글자와
        /// 다른 자리에서 이어진다 — 폭이 같아도 글자가 잘린다.
        func testContinuationKeepsConsumedTextAcrossAShapeChange() throws {
            let words = (1 ... 60).map { "word\($0)" }.joined(separator: " ")
            var paragraph = HwpSynthetic.noteParagraph(
                " " + words,
                // 장식을 안 실은 자동 번호 — 라벨이 **구역 각주 모양**을 따른다.
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1)
            )
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0, 1172, 2344, 0, 1172, 2344]))
            )
            let input = HwpFootnoteLayout.Input(paragraph: paragraph, number: 1)
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let page = Support.geometry(contentWidth: 451)
            let decorated = Support.footnoteShape(head: "(", tail: ")")
            let plain = Support.footnoteShape(head: nil, tail: nil)

            let whole = layout.place(
                footnotes: [input], onPage: page, index: index,
                footnoteShape: decorated, limitsAreaToHalfContent: false
            )
            let full = Support.text(try XCTUnwrap(whole.blocks.first))
            // 앞 세 줄(32.44pt)은 들어가고 전체(67.6pt)는 안 들어가는 자리에서 나눈다.
            let split = layout.place(
                footnotes: [input], onPage: page, index: index,
                footnoteShape: decorated, limitsAreaToHalfContent: false,
                bodyBottom: page.contentFrame.maxY - 54.2
            )
            let head = Support.text(try XCTUnwrap(split.blocks.first))
            expect(split.overflow.count) == 1
            // 이월분은 **장식 없는** 구역에서 다시 조판된다.
            let carried = layout.place(
                footnotes: split.overflow, onPage: page, index: index,
                footnoteShape: plain, limitsAreaToHalfContent: false
            )
            let tail = Support.text(try XCTUnwrap(carried.blocks.first))

            expect(full.hasPrefix(head)) == true
            expect(full.hasSuffix(tail)) == true
            expect(head.count + tail.count) == full.count
        }

        /// 개체가 **뒤 문단**에 붙은 각주도 통째로 CT 높이를 쓴다 (#165 리뷰). 분할 금지는
        /// 각주 단위인데 높이 보존이 문단 단위면, 앞 문단이 캐시 합으로 줄어 그 문단의 마지막
        /// 글줄 위로 뒤 문단의 그림이 올라온다.
        func testObjectInALaterParagraphKeepsEveryParagraphOnCTHeight() throws {
            let text = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄"], locations: [0, 1172, 0, 1172]
            )
            var picture = CoreHwp.HwpParagraph()
            var paraText = CoreHwp.HwpParaText()
            paraText.charArray = "그림 ".utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
                + [CoreHwp.HwpChar(type: .extended, value: 11)]
            picture.paraText = paraText
            picture.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.inlineShapeObject(width: 2000, height: 3000)),
            ]
            picture.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0]))
            )
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let placement = layout.place(
                footnotes: [
                    HwpFootnoteLayout.Input(paragraph: text, number: 1),
                    HwpFootnoteLayout.Input(paragraph: picture, number: 1),
                ],
                onPage: Support.geometry(contentWidth: 451),
                index: HwpIndex(from: CoreHwp.HwpFile()),
                limitsAreaToHalfContent: false
            )
            expect(placement.blocks.count) == 2
            let first = try XCTUnwrap(placement.blocks.first)
            // 네 줄 × 16pt — 캐시 합 46.88pt로 줄면 넷째 줄이 그림 아래로 밀린다.
            expect(first.frame.height).to(beCloseTo(64, within: 1))
            expect(placement.blocks[1].frame.minY).to(beCloseTo(first.frame.maxY, within: 0.01))
        }

        /// 표시 번호가 같은 서로 다른 각주는 **식별자 없이는** 한 각주로 묶인다 (#165 리뷰) —
        /// 남은 자리에 들어가는 이월 조각까지 새 각주와 함께 다음 쪽으로 밀린다.
        func testNotesSharingADisplayNumberMergeWithoutAnIdentity() throws {
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let page = Support.geometry(contentWidth: 451)
            let split = try Support.note(lines: ["첫째 줄", "둘째 줄"], locations: [0, 0])
            // 캐시 없는 새 각주 — 나눌 지점이 없어 그룹이 통째로 밀린다.
            let fresh = HwpSynthetic.noteParagraph(
                " 새 각주",
                autoNumber: HwpSynthetic.autoNumberControl(kind: 1, decorationTail: ")")
            )
            let first = layout.place(
                footnotes: [HwpFootnoteLayout.Input(paragraph: split, number: 1)],
                onPage: page, index: index, limitsAreaToHalfContent: false,
                bodyBottom: page.contentFrame.maxY - 29.2
            )
            let carried = try XCTUnwrap(first.overflow.first)

            // 이월 조각 9.0pt는 남은 12pt에 들어가지만, 같은 번호라 새 각주와 한 그룹이 된다.
            let merged = layout.place(
                footnotes: [carried, HwpFootnoteLayout.Input(paragraph: fresh, number: 1)],
                onPage: page, index: index, limitsAreaToHalfContent: false,
                bodyBottom: page.contentFrame.maxY - 26.2
            )
            expect(merged.blocks).to(beEmpty())
            expect(merged.overflow.count) == 2

            // 식별자를 주면 서로 다른 각주로 갈려 이월 조각이 남은 자리에 실린다.
            let distinct = layout.place(
                footnotes: [
                    carried,
                    HwpFootnoteLayout.Input(paragraph: fresh, number: 1, noteId: 2),
                ],
                onPage: page, index: index, limitsAreaToHalfContent: false,
                bodyBottom: page.contentFrame.maxY - 26.2
            )
            expect(distinct.blocks.count) == 1
            expect(Support.text(try XCTUnwrap(distinct.blocks.first))).to(contain("둘째 줄"))
            expect(distinct.overflow.count) == 1
        }

        /// **글 앞으로** 배치한 그림도 개체 판정에 든다 (#165 리뷰). 높이 하한을 만드는
        /// 개체만 보는 술어(`hasFloatingObject`)로 판정하면 오버레이 개체는 빠지는데, 배치는
        /// 그 개체를 수집해 CT 높이를 지키므로 예약(캐시 합)과 배치(CT)가 갈린다.
        func testOverlayObjectCountsForReservationAndPlacementAlike() throws {
            var note = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄"], locations: [0, 1172, 0, 1172]
            )
            note.ctrlHeaderArray = (note.ctrlHeaderArray ?? []) + [
                .genShapeObject(HwpSynthetic.floatingShapeObject(
                    width: 20000, height: 1000, textWrap: .inFrontOfText
                )),
            ]
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let geometry = Support.geometry(contentWidth: 451)
            let input = HwpFootnoteLayout.Input(paragraph: note, number: 1)
            var coordinator = HwpFootnoteCoordinator(index: index, fontResolver: .testDeterministic)
            let reserved = coordinator.reservedFootnoteHeight(
                for: [input],
                environment: .init(contentWidth: geometry.contentFrame.width, footnoteShape: nil)
            )
            let placement = HwpFootnoteLayout(fontResolver: .testDeterministic).place(
                footnotes: [input], onPage: geometry, index: index, limitsAreaToHalfContent: false
            )
            let block = try XCTUnwrap(placement.blocks.first)
            expect(block.shapes.count) == 1
            expect(reserved).to(beCloseTo(Support.overhead + block.frame.height, within: 0.01))
        }

        /// 오버레이 개체가 **뒤 문단**에만 있어도 각주 전체가 CT 높이를 지킨다 (#165 리뷰) —
        /// 앞 문단이 캐시 합으로 줄면 그 마지막 글줄 위로 뒤 문단의 그림이 올라온다.
        func testOverlayObjectInALaterParagraphKeepsEveryParagraphOnCTHeight() throws {
            let text = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄"], locations: [0, 1172, 0, 1172]
            )
            var picture = try HwpSynthetic.textParagraph("그림 문단")
            picture.ctrlHeaderArray = [
                .genShapeObject(HwpSynthetic.floatingShapeObject(
                    width: 20000, height: 1000, textWrap: .inFrontOfText
                )),
            ]
            picture.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0]))
            )
            let placement = HwpFootnoteLayout(fontResolver: .testDeterministic).place(
                footnotes: [
                    HwpFootnoteLayout.Input(paragraph: text, number: 1),
                    HwpFootnoteLayout.Input(paragraph: picture, number: 1),
                ],
                onPage: Support.geometry(contentWidth: 451),
                index: HwpIndex(from: CoreHwp.HwpFile()),
                limitsAreaToHalfContent: false
            )
            expect(placement.blocks.count) == 2
            expect(placement.blocks.first?.frame.height).to(beCloseTo(64, within: 1))
        }

        /// 첫 호출에서 각주 모양을 생략해 **기본 모양**으로 잰 것도 확정된 상태다 (#165
        /// 리뷰). "아직 안 잼"과 같은 nil로 두면 다음 쪽이 다른 모양을 채택해 문자열이
        /// 밀리고, 이월 조각이 앞 조각의 마지막 글자를 다시 그린다.
        func testContinuationKeepsTheDefaultShapeItWasFirstMeasuredWith() throws {
            let words = (1 ... 60).map { "word\($0)" }.joined(separator: " ")
            var paragraph = HwpSynthetic.noteParagraph(
                " " + words, autoNumber: HwpSynthetic.autoNumberControl(kind: 1)
            )
            paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(
                Support.lineSegPayload(Support.noteLines([0, 1172, 2344, 0, 1172, 2344]))
            )
            let input = HwpFootnoteLayout.Input(paragraph: paragraph, number: 1)
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let index = HwpIndex(from: CoreHwp.HwpFile())
            let page = Support.geometry(contentWidth: 451)

            let whole = layout.place(
                footnotes: [input], onPage: page, index: index, limitsAreaToHalfContent: false
            )
            let full = Support.text(try XCTUnwrap(whole.blocks.first))
            let split = layout.place(
                footnotes: [input], onPage: page, index: index, limitsAreaToHalfContent: false,
                bodyBottom: page.contentFrame.maxY - 54.2
            )
            let head = Support.text(try XCTUnwrap(split.blocks.first))
            // 다음 쪽은 장식 있는 모양을 지정한다 — 이월 조각은 처음 잰 기본 모양을 지켜야 한다.
            let carried = layout.place(
                footnotes: split.overflow, onPage: page, index: index,
                footnoteShape: Support.footnoteShape(head: "(", tail: ")"),
                limitsAreaToHalfContent: false
            )
            let tail = Support.text(try XCTUnwrap(carried.blocks.first))

            expect(full.hasPrefix(head)) == true
            expect(full.hasSuffix(tail)) == true
            expect(head.count + tail.count) == full.count
        }
    }
#endif

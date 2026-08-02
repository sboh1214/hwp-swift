import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    // MARK: - 컨테이너 블록의 링크 계약 (R62)

    /// 각주에만 걸려 있던 세 규약을 표·글상자까지 넓힌 회귀 가드다 (R62):
    /// 자격 영역은 넘쳐 그린 자손까지, 블록-레벨 폴백은 방출과 같은 게이트로,
    /// 감싼 링크는 개체 rect **안**에서만.
    final class HwpContainerBlockLinkHitTests: XCTestCase {
        private let black = HwpRGBColor(red: 0, green: 0, blue: 0)

        // MARK: - ① 자격 영역: 넘쳐 그린 자손

        /// 표 셀의 감싼 개체가 블록 frame을 넘어 그려지면 방출은 **개체 rect**로
        /// 링크를 낸다 — 자격이 frame에서 멈추면 그 링크가 눌리지 않아 "방출 ≡
        /// 히트"가 깨진다. 각주만 자손을 훑던 자격 계산을 컨테이너 공통으로 넓힌다.
        func testTableWrapperLinkOutsideBlockFrameIsHit() {
            let blockFrame = CGRect(x: 50, y: 100, width: 200, height: 50)
            // 셀 도형이 블록 아래로 40pt 넘친다 (페이지 y 130..190 vs frame 100..150)
            let overflow = filledShape(
                rect: CGRect(x: 0, y: 30, width: 60, height: 60),
                wrapperURL: "https://example.com/overflow"
            )
            let block = tableBlock(
                frame: blockFrame,
                cell: cell(CGRect(x: 0, y: 0, width: 200, height: 50), shapes: [overflow])
            )
            let pages = page([block])

            // frame 안쪽 조각 — 종전에도 눌렸다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 80, y: 140)))
                == .hyperlink(url: "https://example.com/overflow", blockIndex: 0)
            // frame 밖으로 넘친 조각 — 방출된 링크가 그대로 눌린다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 80, y: 175)))
                == .hyperlink(url: "https://example.com/overflow", blockIndex: 0)
        }

        // MARK: - ② 블록-레벨 폴백 게이트와 안쪽 우선

        /// 방출은 안쪽 링크를 하나라도 내면 블록 링크를 **내지 않는다**
        /// (`appendHyperlinkCommands`의 `!emitted`). 히트가 `block.hyperlinkURL`을
        /// 먼저 보면 ① 셀 링크가 블록 URL에 뭉개지고 ② 링크 없는 자리에서도 paint
        /// list에 없는 URL이 열린다. 각주에만 있던 계약(R59/R61)을 표에도 건다.
        func testTableBlockLinkYieldsToInnerLinkAndIsGated() {
            let blockFrame = CGRect(x: 50, y: 100, width: 200, height: 50)
            let block = tableBlock(
                frame: blockFrame,
                cell: cell(
                    CGRect(x: 0, y: 0, width: 200, height: 50),
                    paragraphs: [paragraph(
                        rect: CGRect(x: 0, y: 0, width: 200, height: 20),
                        url: "https://example.com/cell"
                    )]
                ),
                hyperlinkURL: "https://example.com/block"
            )
            let pages = page([block])

            // 셀 문단 위 — 안쪽 링크가 이긴다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 60, y: 105)))
                == .hyperlink(url: "https://example.com/cell", blockIndex: 0)
            // 링크 없는 아래쪽 — 블록 링크는 방출되지 않았으므로 표 히트로 떨어진다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 60, y: 140)))
                == .table(blockIndex: 0, row: 0, col: 0)
        }

        /// 게이트는 안쪽 링크가 **없을 때** 블록 링크를 그대로 살린다 (R59) —
        /// 방출이 frame 전체로 내므로 밑줄만 그려지고 탭이 죽으면 안 된다.
        func testTableBlockLinkSurvivesWithoutInnerLink() {
            let block = tableBlock(
                frame: CGRect(x: 50, y: 100, width: 200, height: 50),
                cell: cell(
                    CGRect(x: 0, y: 0, width: 200, height: 50),
                    paragraphs: [paragraph(
                        rect: CGRect(x: 0, y: 0, width: 200, height: 20), url: nil
                    )]
                ),
                hyperlinkURL: "https://example.com/block"
            )
            let pages = page([block])

            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 60, y: 140)))
                == .hyperlink(url: "https://example.com/block", blockIndex: 0)
        }

        // MARK: - ③ 감싼 링크는 개체 rect 안에서만

        /// 자손이 부모를 넘어 그려 가림(`.occluded`)을 돌려줘도, 방출은 부모 rect
        /// 까지만 링크를 낸다 — 그 밖에서 부모의 감싼 URL을 열면 paint list에 없는
        /// 링크가 된다. rect **안**의 칠하지 않은 자리는 여전히 부모 것이다 (R60).
        func testWrapperLinkStopsAtObjectRect() {
            let blockFrame = CGRect(x: 50, y: 100, width: 200, height: 50)
            // 글상자는 40pt인데 자식 도형이 120pt로 아래 80pt를 넘어 그린다
            let wrapped = HwpCellTextbox(
                rect: CGRect(x: 0, y: 0, width: 80, height: 40),
                textbox: HwpTextboxFrame(
                    outerFrame: CGRect(x: 0, y: 0, width: 80, height: 40),
                    paragraphs: [],
                    borderColor: nil, borderWidth: 0, fillColor: nil,
                    shapes: [filledShape(rect: CGRect(x: 0, y: 0, width: 80, height: 120))]
                ),
                paintsBehindText: false,
                zOrder: 0, sourceOrder: 0,
                controlInstanceId: 71
            ).withWrapperURL("https://example.com/wrapper")
            let beneath = AnyHwpBlock(
                frame: CGRect(x: 50, y: 100, width: 400, height: 150),
                kind: .text,
                attributedString: NSAttributedString(string: "본문 링크"),
                hyperlinkURL: "https://example.com/beneath"
            )
            let table = tableBlock(
                frame: blockFrame,
                cell: cell(CGRect(x: 0, y: 0, width: 200, height: 50), textboxes: [wrapped])
            )
            let pages = page([beneath, table])

            // 글상자 rect 안 — 감싼 링크가 열린다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 80, y: 120)))
                == .hyperlink(url: "https://example.com/wrapper", blockIndex: 1)
            // rect 밖 (넘친 자식 위) — 감싼 링크가 아니라 아래 본문 링크다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 80, y: 200)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
        }

        // MARK: - ④ 자격은 stroke까지 (칠의 상위집합)

        /// 도형 테두리는 rect 밖으로 폭의 절반이 나간다 — 자격이 rect에서 멈추면
        /// **보이는 선 위**의 탭이 기각돼 아래 본문 링크가 열린다. 탭 판정
        /// (`ContentLayer.paints`) 이 이미 그 절반을 칠로 세므로 자격이 상위집합이
        /// 아니면 두 판정이 갈린다.
        func testFootnoteShapeStrokeOuterHalfClaimsTap() {
            let blockFrame = CGRect(x: 50, y: 600, width: 100, height: 40)
            // 4pt 테두리 → 위 선은 페이지 y 598..602 에 그려진다
            let shapeRect = CGRect(x: 0, y: 0, width: 300, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                shapes: [HwpCellShape(
                    rect: shapeRect,
                    geometry: HwpShapeGeometry(
                        path: CGPath(rect: shapeRect, transform: nil),
                        fillColor: nil,
                        strokeColor: black.cgColor,
                        strokeWidth: 4
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0, controlInstanceId: 21
                )]
            )
            let beneath = AnyHwpBlock(
                frame: CGRect(x: 50, y: 590, width: 400, height: 60),
                kind: .text,
                attributedString: NSAttributedString(string: "본문 링크"),
                hyperlinkURL: "https://example.com/beneath"
            )
            let pages = page([beneath, AnyHwpBlock(
                frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
            )])

            // rect 위쪽 1pt — 선이 그려진 자리라 각주가 claim한다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 250, y: 599)))
                == .footnote(blockIndex: 1, number: 1)
            // 선 밖 (3pt 위) — 아무것도 안 칠했으므로 아래 본문 링크다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 250, y: 597)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
        }

        /// 글상자 테두리는 페인터가 0.7pt로 끌어올려 긋는다 (`effectiveBorderWidth`)
        /// — 자격이 저작 폭 0.3pt만 보면 **보이는** 절반이 빠진다.
        func testFootnoteThinTextboxBorderClaimsPaintedHalf() {
            let blockFrame = CGRect(x: 50, y: 600, width: 100, height: 40)
            // 0.3pt 저작 → 0.7pt 실선: 위 선은 페이지 y 599.65..600.35
            let boxRect = CGRect(x: 0, y: 0, width: 300, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                textboxes: [HwpCellTextbox(
                    rect: boxRect,
                    textbox: HwpTextboxFrame(
                        outerFrame: boxRect,
                        paragraphs: [],
                        borderColor: black, borderWidth: 0.3, fillColor: nil
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0,
                    controlInstanceId: 23
                )]
            )
            let beneath = AnyHwpBlock(
                frame: CGRect(x: 50, y: 590, width: 400, height: 60),
                kind: .text,
                attributedString: NSAttributedString(string: "본문 링크"),
                hyperlinkURL: "https://example.com/beneath"
            )
            let pages = page([beneath, AnyHwpBlock(
                frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
            )])

            // 실선의 바깥 절반 — 각주가 claim한다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 250, y: 599.8)))
                == .footnote(blockIndex: 1, number: 1)
            // 저작 폭으로도 실선으로도 안 닿는 자리 — 아래 본문 링크다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 250, y: 599.5)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
        }

        // MARK: - R63: 방출 영역 밖 폴백 금지 / 경로 칠 / 색인

        /// 방출은 블록-레벨 폴백을 `block.frame`으로만 낸다 — 자격이 넘쳐 그린 자손까지
        /// 넓어졌으므로 (R62) 그 띠에서도 폴백하면 방출된 적 없는 URL이 열린다.
        func testTableBlockLinkStopsAtBlockFrame() {
            let blockFrame = CGRect(x: 50, y: 100, width: 200, height: 50)
            // 링크 **없는** 도형이 블록 아래로 40pt 넘친다 (페이지 y 130..190)
            let overflow = filledShape(rect: CGRect(x: 0, y: 30, width: 60, height: 60))
            let beneath = AnyHwpBlock(
                frame: CGRect(x: 50, y: 100, width: 400, height: 150),
                kind: .text,
                attributedString: NSAttributedString(string: "본문 링크"),
                hyperlinkURL: "https://example.com/beneath"
            )
            let block = tableBlock(
                frame: blockFrame,
                cell: cell(CGRect(x: 0, y: 0, width: 200, height: 50), shapes: [overflow]),
                hyperlinkURL: "https://example.com/block"
            )
            let pages = page([beneath, block])

            // frame 안 — 방출된 자리라 블록 링크가 열린다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 60, y: 140)))
                == .hyperlink(url: "https://example.com/block", blockIndex: 1)
            // frame 밖 넘친 도형 위 — 그 자리엔 방출된 링크가 없다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 80, y: 175)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
        }

        /// 도형 경로는 rect로 클램프되지 않는다 (렌더 행렬 — 회전·확대). `paints`가
        /// 경로를 보는데 자격이 rect에서 멈추면 **보이는 칠 위**의 탭이 기각돼 아래
        /// 본문 링크가 열린다.
        func testFootnoteShapePathOutsideRectClaimsTap() {
            let blockFrame = CGRect(x: 50, y: 600, width: 100, height: 40)
            // rect는 100pt인데 경로는 300pt까지 칠한다 (회전 행렬이 만드는 모양)
            let shapeRect = CGRect(x: 0, y: 0, width: 100, height: 40)
            let footnote = HwpFootnoteBlock(
                frame: blockFrame,
                paragraphs: [],
                number: 1,
                separatorLine: CGRect(x: 50, y: 590, width: 130, height: 1),
                shapes: [HwpCellShape(
                    rect: shapeRect,
                    geometry: HwpShapeGeometry(
                        path: CGPath(
                            rect: CGRect(x: 0, y: 0, width: 300, height: 40), transform: nil
                        ),
                        fillColor: black.cgColor, strokeColor: nil, strokeWidth: 0
                    ),
                    paintsBehindText: false,
                    zOrder: 0, sourceOrder: 0, controlInstanceId: 21
                )]
            )
            let beneath = AnyHwpBlock(
                frame: CGRect(x: 50, y: 590, width: 400, height: 60),
                kind: .text,
                attributedString: NSAttributedString(string: "본문 링크"),
                hyperlinkURL: "https://example.com/beneath"
            )
            let pages = page([beneath, AnyHwpBlock(
                frame: blockFrame, kind: .footnote, payload: .footnote(footnote)
            )])

            // rect 밖이지만 경로가 칠한 자리 — 각주가 claim한다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 250, y: 620)))
                == .footnote(blockIndex: 1, number: 1)
            // 경로 밖 — 아무것도 안 칠했으므로 아래 본문 링크다
            expect(HwpHitTester().hit(page: pages, point: CGPoint(x: 400, y: 620)))
                == .hyperlink(url: "https://example.com/beneath", blockIndex: 0)
        }

        /// 색인은 `wrapperHyperlinkURL`의 **일괄 형태**여야 한다 — 규칙이 갈리면 방출과
        /// 히트가 다른 URL을 연다. 까다로운 두 규칙을 함께 고정한다: 문단 안에서는 그
        /// 서수의 **첫** run만 보고, 같은 `paraId` 문단이 여럿이면 **앞 문단이 이긴다**.
        func testWrapperLinkIndexMatchesPointLookup() {
            // paraId 7 첫 문단: 서수 0은 링크 없는 run이 먼저, 서수 1은 링크 있음
            let first = NSMutableAttributedString(string: "\u{FFFC}\u{FFFC}")
            first.addAttribute(
                HwpAttributedStringKey.controlIndex, value: 0, range: NSRange(location: 0, length: 1)
            )
            first.addAttribute(
                HwpAttributedStringKey.controlIndex, value: 1, range: NSRange(location: 1, length: 1)
            )
            first.addAttribute(
                HwpAttributedStringKey.hyperlink, value: "https://example.com/one",
                range: NSRange(location: 1, length: 1)
            )
            // paraId 7 둘째 문단: 서수 0에 링크 — 첫 문단이 nil이라 여기까지 온다
            let second = NSMutableAttributedString(string: "\u{FFFC}")
            let head = NSRange(location: 0, length: 1)
            second.addAttribute(HwpAttributedStringKey.controlIndex, value: 0, range: head)
            second.addAttribute(
                HwpAttributedStringKey.hyperlink, value: "https://example.com/late", range: head
            )
            // paraId 9: 같은 서수라도 다른 문단이면 다른 링크다 (R51 #1)
            let other = NSMutableAttributedString(string: "\u{FFFC}")
            other.addAttribute(HwpAttributedStringKey.controlIndex, value: 0, range: head)
            other.addAttribute(
                HwpAttributedStringKey.hyperlink, value: "https://example.com/other", range: head
            )
            let paragraphs = [
                wrapperParagraph(first, paragraphId: 7),
                wrapperParagraph(second, paragraphId: 7),
                wrapperParagraph(other, paragraphId: 9),
            ]

            let index = HwpDrawnTextLayout.wrapperHyperlinkIndex(in: paragraphs)
            for (paragraphId, controlIndex) in [
                (UInt32(7), 0), (UInt32(7), 1), (UInt32(9), 0), (UInt32(7), 2),
            ] {
                let key = HwpWrapperLinkKey(paragraphId: paragraphId, controlIndex: controlIndex)
                let pointLookup = HwpDrawnTextLayout.wrapperHyperlinkURL(
                    in: paragraphs, paragraphId: paragraphId, controlIndex: controlIndex
                )
                if let pointLookup {
                    expect(index[key]) == pointLookup
                } else {
                    expect(index[key]).to(beNil())
                }
            }
            // 규칙이 실제로 그 값인지도 못박는다 (양쪽이 함께 틀리는 것을 막는다)
            expect(index[HwpWrapperLinkKey(paragraphId: 7, controlIndex: 0)])
                == "https://example.com/late"
            expect(index[HwpWrapperLinkKey(paragraphId: 7, controlIndex: 1)])
                == "https://example.com/one"
            expect(index[HwpWrapperLinkKey(paragraphId: 9, controlIndex: 0)])
                == "https://example.com/other"
            expect(index[HwpWrapperLinkKey(paragraphId: 7, controlIndex: 2)]).to(beNil())
        }

        // MARK: - 헬퍼

        private func filledShape(rect: CGRect, wrapperURL: String? = nil) -> HwpCellShape {
            let shape = HwpCellShape(
                rect: rect,
                geometry: HwpShapeGeometry(
                    path: CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil),
                    fillColor: black.cgColor, strokeColor: nil, strokeWidth: 0
                ),
                paintsBehindText: false,
                zOrder: 0, sourceOrder: 0,
                controlInstanceId: 60
            )
            guard let wrapperURL else { return shape }
            return shape.withWrapperURL(wrapperURL)
        }

        private func wrapperParagraph(
            _ attributed: NSAttributedString, paragraphId: UInt32
        ) -> HwpLaidOutParagraph {
            HwpLaidOutParagraph(
                attributedString: attributed,
                frame: HwpParagraphFrame(totalHeight: 20, lines: []),
                rect: CGRect(x: 0, y: 0, width: 200, height: 20),
                paragraphId: paragraphId,
                hyperlinkURL: nil
            )
        }

        private func paragraph(rect: CGRect, url: String?) -> HwpLaidOutParagraph {
            HwpLaidOutParagraph(
                attributedString: NSAttributedString(string: "셀 글자"),
                frame: HwpParagraphFrame(totalHeight: rect.height, lines: []),
                rect: rect,
                paragraphId: 1,
                hyperlinkURL: url
            )
        }

        private func cell(
            _ localFrame: CGRect,
            paragraphs: [HwpLaidOutParagraph] = [],
            shapes: [HwpCellShape] = [],
            textboxes: [HwpCellTextbox] = []
        ) -> HwpTableCellFrame {
            HwpTableCellFrame(
                cellFrame: localFrame,
                row: 0, column: 0, rowSpan: 1, columnSpan: 1,
                paragraphs: paragraphs,
                borders: .uniform(width: 0.5, color: black),
                fillColor: nil,
                shapes: shapes,
                textboxes: textboxes
            )
        }

        private func tableBlock(
            frame: CGRect, cell: HwpTableCellFrame, hyperlinkURL: String? = nil
        ) -> AnyHwpBlock {
            AnyHwpBlock(
                frame: frame,
                kind: .table,
                hyperlinkURL: hyperlinkURL,
                payload: .table(HwpTableFrame(
                    outerFrame: CGRect(origin: .zero, size: frame.size),
                    rows: [HwpTableRowFrame(rowFrame: cell.cellFrame, cells: [cell])],
                    borderColor: black, borderWidth: 1
                ))
            )
        }

        private func page(_ blocks: [AnyHwpBlock]) -> HwpPage {
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: blocks,
                pageNumber: 1
            )
        }
    }
#endif

import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 각주 이어짐 (#165) PR 리뷰가 잡은 **개체 판정** 결함의 재현 — "개체를 담은 각주"(쪽 끝
    /// 분할 금지)의 술어가 수집기가 실제로 그리는 것과 같은지. 조각·측정 결함은
    /// `HwpFootnoteContinuationSourceLayoutTests`, 예약은 `HwpFootnoteContinuationReservationTests`
    /// (클래스 본문이 SwiftLint type_body_length 상한에 닿아 갈라 뒀다), 조립 헬퍼는
    /// `FootnoteContinuationSupport`.
    final class HwpFootnoteContinuationObjectTests: XCTestCase {
        private typealias Support = FootnoteContinuationSupport

        /// 요소가 하나도 없는 도형 컨트롤은 개체를 내지 않으므로 "개체를 담은 각주"가 아니다
        /// (#165 리뷰) — 공허하게 참인 판정은 쪽 끝 분할을 막아 각주를 통째로 넘긴다.
        func testEmptyShapeControlDoesNotBlockSplitting() throws {
            var note = try Support.note(
                lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                locations: [0, 1172, 2344, 0, 1172]
            )
            var object = HwpSynthetic.floatingShapeObject(
                width: 1000, height: 1000, textWrap: .inFrontOfText
            )
            object.shapeComponentArray = []
            note.ctrlHeaderArray = (note.ctrlHeaderArray ?? []) + [.genShapeObject(object)]
            expect(HwpParagraphObjectCollector.hasCollectibleObject(
                in: note, collectsTextboxes: true, collectsTables: true
            )) == false

            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let geometry = Support.geometry(contentWidth: 451)
            // 앞 세 줄(32.44pt)은 들어가고 전체(55.88pt)는 안 들어가는 자리 — 나눠야 한다.
            let placement = layout.place(
                footnotes: [HwpFootnoteLayout.Input(paragraph: note, number: 1)],
                onPage: geometry, index: HwpIndex(from: CoreHwp.HwpFile()),
                limitsAreaToHalfContent: false, bodyBottom: geometry.contentFrame.maxY - 50
            )
            expect(placement.blocks.count) == 1
            expect(placement.overflow.first?.placedLineCount) == 3
        }

        /// 관문을 지난 요소도 그릴 것이 없을 수 있다 (#165 리뷰): BinData 참조 없는 그림·크기 0인
        /// 도형은 `objects()`가 아무것도 내지 않으므로 "개체를 담은 각주"가 아니다 — 그런 각주는
        /// 쪽 끝에서 나뉘어 이어져야 한다. 보통 도형은 여전히 개체다.
        func testControlsThatEmitNothingDoNotCountAsObjects() throws {
            func note(with control: CoreHwp.HwpCtrlId) throws -> CoreHwp.HwpParagraph {
                var note = try Support.note(
                    lines: ["첫째 줄", "둘째 줄", "셋째 줄", "넷째 줄", "다섯째 줄"],
                    locations: [0, 1172, 2344, 0, 1172]
                )
                note.ctrlHeaderArray = (note.ctrlHeaderArray ?? []) + [control]
                return note
            }
            func carries(_ paragraph: CoreHwp.HwpParagraph) -> Bool {
                HwpParagraphObjectCollector.hasCollectibleObject(
                    in: paragraph, collectsTextboxes: true, collectsTables: true
                )
            }
            // BinData 참조가 없는 그림 — `image()`가 nil이라 그려지지 않는다.
            var orphanPicture = HwpSynthetic.inlineShapeObject(width: 1000, height: 1000)
            var component = orphanPicture.shapeComponentArray[0]
            component.pictureArray = [CoreHwp.HwpShapeComponentPicture(
                rawPayload: Data(), binaryDataId: nil, rawTrailing: nil, unknownChildren: []
            )]
            orphanPicture.shapeComponentArray[0] = component
            expect(carries(try note(with: .genShapeObject(orphanPicture)))) == false
            // 크기 0인 도형 — `resolvedSize`가 nil이라 그려지지 않는다.
            let zeroShape = HwpSynthetic.inlineShapeObject(width: 0, height: 0)
            expect(carries(try note(with: .genShapeObject(zeroShape)))) == false
            // 보통 도형은 개체다.
            let shape = HwpSynthetic.inlineShapeObject(width: 1000, height: 1000)
            expect(carries(try note(with: .genShapeObject(shape)))) == true

            // 그려지지 않는 그림을 단 각주는 나뉜다.
            let layout = HwpFootnoteLayout(fontResolver: .testDeterministic)
            let geometry = Support.geometry(contentWidth: 451)
            let placement = layout.place(
                footnotes: [HwpFootnoteLayout.Input(
                    paragraph: try note(with: .genShapeObject(orphanPicture)), number: 1
                )],
                onPage: geometry, index: HwpIndex(from: CoreHwp.HwpFile()),
                limitsAreaToHalfContent: false, bodyBottom: geometry.contentFrame.maxY - 50
            )
            expect(placement.blocks.count) == 1
            expect(placement.overflow.first?.placedLineCount) == 3
        }
    }
#endif

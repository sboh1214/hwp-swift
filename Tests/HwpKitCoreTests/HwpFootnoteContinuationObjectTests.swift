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

        /// 도형의 관문은 **크기**다 (PR 리뷰): `shape()`는 `resolvedSize`를 먼저 요구하므로 선·사각형
        /// 세부 레코드가 있어도 공통 속성·요소 크기가 모두 0이면 그리지 않는다 — 그런 각주를 세부
        /// 레코드만 보고 "개체를 담은 각주"로 판정하면 쪽 끝 분할이 막힌다. 크기는 `resolvedSize`
        /// 처럼 **축마다** 폴백한다 — 공통 속성의 너비와 요소의 현재 높이로 크기가 서는 도형은
        /// 그려지므로 개체다. 두 판정 모두 수집기가 실제로 내는 것과 대조한다.
        func testShapeDetailWithoutSizeDoesNotCountAsObject() throws {
            func note(with control: CoreHwp.HwpCtrlId) throws -> CoreHwp.HwpParagraph {
                var note = try Support.note(
                    lines: ["첫째 줄", "둘째 줄", "셋째 줄"], locations: [0, 1172, 2344]
                )
                note.ctrlHeaderArray = (note.ctrlHeaderArray ?? []) + [control]
                return note
            }
            func carries(_ paragraph: CoreHwp.HwpParagraph) -> Bool {
                HwpParagraphObjectCollector.hasCollectibleObject(
                    in: paragraph, collectsTextboxes: true, collectsTables: true
                )
            }
            // 선 세부 레코드는 있지만 크기가 없는 도형 — `resolvedSize`가 nil이라 그려지지 않는다.
            var lineWithoutSize = HwpSynthetic.inlineShapeObject(width: 0, height: 0)
            var component = lineWithoutSize.shapeComponentArray[0]
            component.lineArray = [CoreHwp.HwpShapeComponentLine(
                rawPayload: Self.littleEndian([0, 0, 1000, 1000]), unknownChildren: []
            )]
            lineWithoutSize.shapeComponentArray[0] = component
            let lineNote = try note(with: .genShapeObject(lineWithoutSize))
            expect(Self.emittedObjectCount(in: lineNote)) == 0
            expect(carries(lineNote)) == false

            // 공통 속성은 너비만, 요소는 현재 높이만 — 축마다 폴백한 크기가 서므로 그려진다.
            var mixedAxes = HwpSynthetic.inlineShapeObject(width: 1000, height: 0)
            var mixedComponent = mixedAxes.shapeComponentArray[0]
            var elementPayload = Self.littleEndian([0x2464_6F24]) // ctrl id 1회
            elementPayload.append(Data(count: 20)) // 그룹 오프셋·개수·버전·처음 크기
            elementPayload.append(Self.littleEndian([0, 1000])) // 현재 너비 0·현재 높이 1000
            elementPayload.append(Data(count: 14)) // 뒤집기·회전
            mixedComponent.rawPayload = elementPayload
            mixedAxes.shapeComponentArray[0] = mixedComponent
            expect(mixedComponent.detail?.currentHeight) == 1000
            let mixedNote = try note(with: .genShapeObject(mixedAxes))
            expect(Self.emittedObjectCount(in: mixedNote)) == 1
            expect(carries(mixedNote)) == true
        }

        /// 수집기가 실제로 내는 개체 수 — 술어(`hasCollectibleObject`)의 대조 상대.
        private static func emittedObjectCount(in paragraph: CoreHwp.HwpParagraph) -> Int {
            let collector = HwpParagraphObjectCollector(
                index: HwpIndex(from: CoreHwp.HwpFile()), fontResolver: .testDeterministic,
                sizeResolver: nil, collectsTextboxes: true, attributeCache: nil,
                collectsTables: true
            )
            let objects = collector.objects(
                in: paragraph,
                frame: HwpParagraphFrame(totalHeight: 10, lines: []),
                paragraphRect: CGRect(x: 0, y: 0, width: 200, height: 10)
            )
            return objects.shapes.count + objects.images.count + objects.textboxes.count
        }

        private static func littleEndian(_ values: [UInt32]) -> Data {
            var data = Data()
            for value in values {
                withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            }
            return data
        }
    }
#endif

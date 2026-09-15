import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 호환 문서 대상 프로그램(표 55)이 조판 문자열에 실리는 계약 (#187) — 렌더러가 MS
    /// 워드 호환 문서의 장식선 기하를 가르는 열쇠다. `extension`에 두는 이유는
    /// `HwpTextRunBuilderTests` 본문이 `type_body_length` 경고선에 닿아 있어서다.
    extension HwpTextRunBuilderTests {
        private func builder(
            shapes: [UInt32: CoreHwp.HwpCharShape],
            target: CoreHwp.HwpCompatibleDocumentTarget?
        ) -> HwpTextRunBuilder {
            HwpTextRunBuilder(
                index: HwpIndex(
                    charShapes: shapes,
                    paraShapes: [:],
                    borderFills: [:],
                    tabDefs: [:],
                    styles: [:],
                    bullets: [:],
                    numberings: [:],
                    binData: [:],
                    faceNamesKorean: [:],
                    faceNamesEnglish: [:],
                    faceNamesChinese: [:],
                    faceNamesJapanese: [:],
                    faceNamesEtc: [:],
                    faceNamesSymbol: [:],
                    faceNamesUser: [:],
                    isCompatibilityDocument: target != nil && target != .hwp201X,
                    compatibleDocumentTarget: target
                ),
                fontResolver: .testDeterministic
            )
        }

        /// MS 워드 호환 문서의 모든 run이 대상 프로그램 키를 싣는다 — 장식이 없는 run도.
        func testMsWordDocumentCarriesTheTargetOnEveryRun() throws {
            let paragraph = paragraph(text: "가A", runs: [(0, 0), (1, 1)])
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [
                0: try charShape(), 1: try charShape(property: 1 << 18),
            ]
            let built = builder(shapes: shapes, target: .msWord).build(paragraph: paragraph)
            for location in 0 ..< built.length {
                let value = built.attribute(
                    HwpAttributedStringKey.compatibleDocumentTarget, at: location,
                    effectiveRange: nil
                ) as? NSNumber
                expect(value?.uint32Value).to(
                    equal(HwpCompatibleDocumentTarget.msWord.rawValue), description: "\(location)"
                )
            }
        }

        /// 한글 문서(record 없음·`HWP201X`)에는 키가 없다 — 없음이 곧 기본값이다.
        func testNativeDocumentCarriesNoTarget() throws {
            let paragraph = paragraph(text: "가", runs: [(0, 0)])
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [0: try charShape(property: 1 << 18)]
            for target in [nil, CoreHwp.HwpCompatibleDocumentTarget.hwp201X] {
                let built = builder(shapes: shapes, target: target).build(paragraph: paragraph)
                expect(built.attribute(
                    HwpAttributedStringKey.compatibleDocumentTarget, at: 0, effectiveRange: nil
                )).to(beNil(), description: String(describing: target))
                expect(built.attribute(
                    HwpAttributedStringKey.msWordParagraphEndBox, at: 0, effectiveRange: nil
                )).to(beNil())
            }
        }

        /// 한글 2007 호환·훈민정음 호환도 키를 싣되 값이 다르다 — 렌더러는 `msWord`만
        /// 가르므로 한글 문서와 같은 기하가 된다.
        func testOtherTargetsCarryTheirOwnRawValue() throws {
            let paragraph = paragraph(text: "가", runs: [(0, 0)])
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [0: try charShape()]
            for target in [CoreHwp.HwpCompatibleDocumentTarget.hwp200X, .hunmin] {
                let built = builder(shapes: shapes, target: target).build(paragraph: paragraph)
                let value = built.attribute(
                    HwpAttributedStringKey.compatibleDocumentTarget, at: 0, effectiveRange: nil
                ) as? NSNumber
                expect(value?.uint32Value) == target.rawValue
            }
        }

        /// 문단 끝 글자의 줄 상자는 MS 워드 호환 문서의 **마지막 글자에만** 실린다 —
        /// 값은 마지막 글자 모양의 라틴 슬롯 글꼴(결정론 resolver: Menlo)을 그 크기로
        /// 푼 상자다 (12pt × Menlo 1.513/1.1028).
        func testMsWordParagraphEndBoxRidesOnTheLastCharacter() throws {
            let paragraph = paragraph(text: "가나", runs: [(0, 0)])
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [0: try charShape()]
            let built = builder(shapes: shapes, target: .msWord).build(paragraph: paragraph)
            expect(built.attribute(
                HwpAttributedStringKey.msWordParagraphEndBox, at: 0, effectiveRange: nil
            )).to(beNil())
            let last = built.attribute(
                HwpAttributedStringKey.msWordParagraphEndBox, at: built.length - 1,
                effectiveRange: nil
            ) as? [NSNumber]
            let numbers = try XCTUnwrap(last)
            expect(numbers.count) == 2
            let menlo = CTFontCreateWithName("Menlo" as CFString, 12, nil)
            let expected = HwpMsWordLineBox.metrics(of: menlo).scaled(by: 12)
            expect(CGFloat(numbers[0].doubleValue))
                .to(beCloseTo(expected.lineHeight, within: 0.001))
            expect(CGFloat(numbers[1].doubleValue))
                .to(beCloseTo(expected.baseline, within: 0.001))
        }

        /// 변경 추적 표식은 삽입 밑줄 색·삭제선 키만 싣고 별도 기하 키가 없다 — 두 선은
        /// 일반 밑줄·취소선과 같은 경로로 그려진다 (#187 실측).
        func testTrackChangeMarksReuseTheOrdinaryLineKeys() throws {
            var paragraph = paragraph(text: "가나다", runs: [(0, 0)])
            paragraph.paraRangeTagArray = [
                try rangeTag(start: 0, end: 1, kind: 16),
                try rangeTag(start: 1, end: 2, kind: 17),
            ]
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [0: try charShape()]
            let built = builder(shapes: shapes, target: nil).build(paragraph: paragraph)
            let inserted = built.attributes(at: 0, effectiveRange: nil)
            expect(inserted[HwpAttributedStringKey.trackInsertUnderline]).toNot(beNil())
            expect(inserted[HwpAttributedStringKey.underlineStyle]).to(beNil())
            let deleted = built.attributes(at: 1, effectiveRange: nil)
            expect(deleted[HwpAttributedStringKey.strikethroughStyle]).toNot(beNil())
            expect(deleted[HwpAttributedStringKey.strikethroughColor]).toNot(beNil())
            expect(deleted[HwpAttributedStringKey.trackInsertUnderline]).to(beNil())
            let plain = built.attributes(at: 2, effectiveRange: nil)
            expect(plain[HwpAttributedStringKey.strikethroughStyle]).to(beNil())
            expect(plain[HwpAttributedStringKey.trackInsertUnderline]).to(beNil())
        }
    }
#endif

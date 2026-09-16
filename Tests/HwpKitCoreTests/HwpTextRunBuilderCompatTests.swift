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

        /// 문단 끝 글자의 줄 상자는 MS 워드 호환 문서에서 **마지막 글자가 속한 속성 run
        /// 전체**에 실린다 — 글자 모양이 다른 두 run `가나`+`A`는 마지막 run `A`에만,
        /// `가나` 한 run은 두 글자 모두에 (마지막 글자 하나에만 얹으면 속성 경계가 글리프
        /// 조합을 가른다, PR 리뷰; 결정론 resolver는 한글·라틴 슬롯이 같은 Menlo라 슬롯이
        /// 아니라 글자 모양으로 run을 가른다). 값은 마지막 글자 모양의 라틴 슬롯 글꼴
        /// (결정론 resolver: Menlo)을 그 크기로 푼 상자다 (12pt × Menlo 1.513/1.1028).
        func testMsWordParagraphEndBoxRidesOnTheLastRun() throws {
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [
                0: try charShape(), 1: try charShape(property: 1 << 18),
            ]
            let mixed = builder(shapes: shapes, target: .msWord)
                .build(paragraph: paragraph(text: "가나A", runs: [(0, 0), (2, 1)]))
            let carried = (0 ..< mixed.length).map { location in
                mixed.attribute(
                    HwpAttributedStringKey.msWordParagraphEndBox, at: location, effectiveRange: nil
                ) != nil
            }
            expect(carried) == [false, false, true]
            let hangul = builder(shapes: shapes, target: .msWord)
                .build(paragraph: paragraph(text: "가나", runs: [(0, 0)]))
            var range = NSRange(location: 0, length: 0)
            let last = hangul.attribute(
                HwpAttributedStringKey.msWordParagraphEndBox, at: hangul.length - 1,
                effectiveRange: &range
            ) as? [NSNumber]
            expect(range) == NSRange(location: 0, length: 2)
            let numbers = try XCTUnwrap(last)
            expect(numbers.count) == 2
            let menlo = CTFontCreateWithName("Menlo" as CFString, 12, nil)
            let expected = HwpMsWordLineBox.metrics(of: menlo).scaled(by: 12)
            expect(CGFloat(numbers[0].doubleValue))
                .to(beCloseTo(expected.lineHeight, within: 0.001))
            expect(CGFloat(numbers[1].doubleValue))
                .to(beCloseTo(expected.baseline, within: 0.001))
        }

        /// 문단 끝 상자는 글리프 조합 경계를 바꾸지 않는다 (PR 리뷰) — 이모지 서로게이트
        /// 쌍·결합 문자 `é`·합자 후보 `fi`·커닝 쌍 `AV`·아랍어 합자 `لا`로 끝나는 문단의
        /// CoreText run 범위·글리프 수·줄 폭이 한글 문서와 같고, 마지막 run이 상자를
        /// 싣는다. 마지막 UTF-16 단위에만 얹으면 `😀`가 LastResort 글리프 둘(폭 74.6 →
        /// 122.6pt)로 깨지고 `é`·`لا`는 CoreText가 조합을 지키며 속성을 버렸다.
        func testMsWordParagraphEndBoxKeepsGlyphComposition() throws {
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [0: try charShape()]
            func runs(_ built: NSAttributedString) throws -> [(range: NSRange, glyphs: Int)] {
                let line = CTLineCreateWithAttributedString(built)
                let runs = try XCTUnwrap(CTLineGetGlyphRuns(line) as? [CTRun])
                return runs.map { run in
                    let range = CTRunGetStringRange(run)
                    return (NSRange(location: range.location, length: range.length),
                            CTRunGetGlyphCount(run))
                }
            }
            for text in ["가😀", "가e\u{301}", "가fi", "AVA", "ab\u{0644}\u{0627}"] {
                let paragraph = paragraph(text: text, runs: [(0, 0)])
                let native = builder(shapes: shapes, target: nil).build(paragraph: paragraph)
                let word = builder(shapes: shapes, target: .msWord).build(paragraph: paragraph)
                let nativeRuns = try runs(native)
                let wordRuns = try runs(word)
                expect(wordRuns.map(\.range)).to(
                    equal(nativeRuns.map(\.range)), description: "\(text) run 범위"
                )
                expect(wordRuns.map(\.glyphs)).to(
                    equal(nativeRuns.map(\.glyphs)), description: "\(text) 글리프 수"
                )
                let nativeWidth = CTLineGetTypographicBounds(
                    CTLineCreateWithAttributedString(native), nil, nil, nil
                )
                let wordWidth = CTLineGetTypographicBounds(
                    CTLineCreateWithAttributedString(word), nil, nil, nil
                )
                expect(wordWidth).to(beCloseTo(nativeWidth, within: 0.001), description: text)
                let lastRun = try XCTUnwrap(
                    (CTLineGetGlyphRuns(CTLineCreateWithAttributedString(word)) as? [CTRun])?.last
                )
                let attributes = CTRunGetAttributes(lastRun) as? [NSAttributedString.Key: Any]
                expect(attributes?[HwpAttributedStringKey.msWordParagraphEndBox]).toNot(
                    beNil(), description: "\(text) 마지막 run의 끝 상자"
                )
            }
        }

        /// 모든 run이 글자 모양 id(`charShapeId`)를 싣는다 — 렌더러가 슬롯·대체 글꼴로
        /// 쪼개진 run을 글자 모양 단위로 되묶는 열쇠다 (#187 리뷰). 문서에 없는 id의 폴백
        /// 모양은 싣지 않고, 한글 문서도 싣는다.
        func testRunsCarryTheirCharShapeId() throws {
            let paragraph = paragraph(text: "가A나B", runs: [(0, 0), (1, 1), (2, 0), (3, 9)])
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [
                0: try charShape(), 1: try charShape(property: 1 << 18),
            ]
            for target: CoreHwp.HwpCompatibleDocumentTarget? in [.msWord, nil] {
                let built = builder(shapes: shapes, target: target).build(paragraph: paragraph)
                let ids = (0 ..< built.length).map { location in
                    (built.attribute(
                        HwpAttributedStringKey.charShapeId, at: location, effectiveRange: nil
                    ) as? NSNumber)?.uint32Value
                }
                expect(ids).to(equal([0, 1, 0, nil]), description: "\(String(describing: target))")
            }
        }

        /// 한 줄 끝(LF)·빈 줄 앵커 표식 run도 대상 프로그램 키를 물려받는다 — 렌더러의
        /// MS 워드 호환 줄 상자 판정이 run 단위라 표식만 남은 줄도 갈래를 알아야 하고,
        /// 표식 run의 글꼴도 줄 상자 후보다 (#187 리뷰).
        func testMarkerRunsKeepTheCompatibleDocumentTarget() throws {
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [0: try charShape()]
            let lineBreak = builder(shapes: shapes, target: .msWord)
                .build(paragraph: paragraph(text: "가\u{0A}나\u{0D}", runs: [(0, 0)]))
            let marker = lineBreak.attributes(at: 1, effectiveRange: nil)
            expect(marker[HwpAttributedStringKey.lineBreak]).toNot(beNil())
            let markerTarget = marker[HwpAttributedStringKey.compatibleDocumentTarget] as? NSNumber
            expect(markerTarget?.uint32Value) == HwpCompatibleDocumentTarget.msWord.rawValue
            let anchor = builder(shapes: shapes, target: .msWord)
                .build(paragraph: paragraph(text: "가\u{0A}\u{0D}", runs: [(0, 0)]))
            expect(anchor.string) == "가\u{0A} "
            let anchorAttributes = anchor.attributes(at: 2, effectiveRange: nil)
            expect((anchorAttributes[HwpAttributedStringKey.compatibleDocumentTarget] as? NSNumber)?
                .uint32Value) == HwpCompatibleDocumentTarget.msWord.rawValue
            // 한글 문서의 표식은 키가 없다.
            let native = builder(shapes: shapes, target: nil)
                .build(paragraph: paragraph(text: "가\u{0A}나\u{0D}", runs: [(0, 0)]))
            expect(native.attribute(
                HwpAttributedStringKey.compatibleDocumentTarget, at: 1, effectiveRange: nil
            )).to(beNil())
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

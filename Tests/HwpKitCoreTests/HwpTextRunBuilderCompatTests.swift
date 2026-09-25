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

        /// 한글 2007 호환·훈민정음 호환도 키를 싣되 값이 다르다 — 렌더러는 이 raw 값으로
        /// `msWord`(글꼴 지표 기하)와 `hwp200X`(고정 두께 기하, #210)를 가르고 훈민정음은
        /// 한글 문서와 같이 그린다. 이 계약이 두 기하의 전제다.
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

        /// 문단 끝 글자의 줄 상자는 MS 워드 호환 문서에서 **문단 조판 문자열 전체**에
        /// 실린다 — 글자 모양이 다른 두 run `가나`+`A`도 세 글자 모두 (마지막 글자 하나에만
        /// 얹으면 속성 경계가 글리프 조합을 가르고, 마지막 run에만 얹으면 앞 run에 합자로
        /// 흡수될 때 상자를 잃는다, PR 리뷰). 값은 **마지막** 글자 모양의 라틴 슬롯 글꼴
        /// (결정론 resolver: Menlo)을 그 크기로 푼 상자다 (12pt × Menlo 1.513/1.1028).
        func testMsWordParagraphEndBoxRidesOnTheWholeParagraph() throws {
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
            expect(carried) == [true, true, true]
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

        /// 문단 끝 상자는 라틴 슬롯 상대 크기가 아니라 **글자 모양 기본 크기**로 잰다 —
        /// 라틴 50%(Menlo 6pt)인 12pt 글자 모양의 끝 상자는 Menlo × 12pt다 (한글 실측:
        /// 슬롯 상대 크기는 MS 워드 호환 상자에 들지 않는다, PR 리뷰).
        func testMsWordParagraphEndBoxUsesTheBaseSizeNotTheLatinSlotSize() throws {
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [
                0: try charShape(faceRelativeSize: [100, 50, 100, 100, 100, 100, 100]),
            ]
            let built = builder(shapes: shapes, target: .msWord)
                .build(paragraph: paragraph(text: "가A", runs: [(0, 0)]))
            let latinFont = try XCTUnwrap(
                fontRanges(in: built).first { NSLocationInRange(1, $0.range) }?.font
            )
            expect(CTFontGetSize(latinFont)).to(beCloseTo(6, within: 0.001))
            let numbers = try XCTUnwrap(built.attribute(
                HwpAttributedStringKey.msWordParagraphEndBox, at: 0, effectiveRange: nil
            ) as? [NSNumber])
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
        /// 122.6pt)로 깨지고 `é`·`لا`는 CoreText가 조합을 지키며 속성을 버렸다. 뒤 두 사례는
        /// 글자 모양이 갈리는 run 경계를 합자가 가로지른다(`لا`의 `ا`·`é`의 결합 악센트만
        /// 글자 모양 1) — 마지막 run에만 얹으면 CoreText가 앞 run의 속성만 남겨 상자를
        /// 버렸다 (두 번째 PR 리뷰).
        func testMsWordParagraphEndBoxKeepsGlyphComposition() throws {
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [
                0: try charShape(), 1: try charShape(property: 1 << 18),
            ]
            func runs(_ built: NSAttributedString) throws -> [(range: NSRange, glyphs: Int)] {
                let line = CTLineCreateWithAttributedString(built)
                let runs = try XCTUnwrap(CTLineGetGlyphRuns(line) as? [CTRun])
                return runs.map { run in
                    let range = CTRunGetStringRange(run)
                    return (NSRange(location: range.location, length: range.length),
                            CTRunGetGlyphCount(run))
                }
            }
            let cases: [(text: String, runs: [(UInt32, UInt32)])] = [
                ("가😀", [(0, 0)]), ("가e\u{301}", [(0, 0)]), ("가fi", [(0, 0)]),
                ("AVA", [(0, 0)]), ("ab\u{0644}\u{0627}", [(0, 0)]),
                ("ab\u{0644}\u{0627}", [(0, 0), (3, 1)]), ("가e\u{301}", [(0, 0), (2, 1)]),
            ]
            for (text, shapeRuns) in cases {
                let paragraph = paragraph(text: text, runs: shapeRuns)
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

        /// MS 워드 호환 문서의 빈 문단 앵커와 빈 줄 앵커는 **라틴 슬롯** 글꼴이다 (#194) —
        /// 그 자리는 문단 끝 글자(CR)뿐이고 한글은 CR을 라틴 슬롯 글꼴로 줄 상자에 세운다
        /// (한글 실측: Apple SD/Menlo 10pt 글자 모양의 빈 문단 `vertsize` 1515 = Menlo).
        /// 라틴 50%(6pt)인 12pt 글자 모양으로 슬롯을 가른다 — 한글 문서는 종전대로 한글
        /// 슬롯(12pt)이다.
        func testMsWordEmptyAnchorsUseTheLatinSlotFont() throws {
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [
                0: try charShape(faceRelativeSize: [100, 50, 100, 100, 100, 100, 100]),
            ]
            func anchorSize(_ text: String, target: CoreHwp.HwpCompatibleDocumentTarget?) throws -> CGFloat {
                let built = builder(shapes: shapes, target: target)
                    .build(paragraph: paragraph(text: text, runs: [(0, 0)]))
                expect(built.attribute(
                    HwpAttributedStringKey.emptyLineAnchor, at: built.length - 1, effectiveRange: nil
                )).toNot(beNil())
                let font = try XCTUnwrap(fontRanges(in: built).last?.font)
                return CTFontGetSize(font)
            }
            expect(try anchorSize("\u{0D}", target: .msWord)).to(beCloseTo(6, within: 0.001))
            expect(try anchorSize("가\u{0A}\u{0D}", target: .msWord)).to(beCloseTo(6, within: 0.001))
            // 한글 문서는 종전대로다 — 빈 문단 앵커는 한글 슬롯(12pt), 한 줄 끝 뒤의 빈 줄
            // 앵커는 빈칸의 스크립트 판정(기본 `.english`)대로 라틴 슬롯(6pt). 상자가 글꼴과
            // 무관하니 어느 쪽이든 줄 높이는 같다.
            expect(try anchorSize("\u{0D}", target: nil)).to(beCloseTo(12, within: 0.001))
            expect(try anchorSize("가\u{0A}\u{0D}", target: nil)).to(beCloseTo(6, within: 0.001))
            // 빈 줄 앵커의 다른 속성(기본 크기·호환 문서 키)은 그대로다.
            let built = builder(shapes: shapes, target: .msWord)
                .build(paragraph: paragraph(text: "가\u{0A}\u{0D}", runs: [(0, 0)]))
            let anchor = built.attributes(at: 2, effectiveRange: nil)
            expect((anchor[HwpAttributedStringKey.baseFontSize] as? NSNumber)?.doubleValue) == 12
            expect((anchor[HwpAttributedStringKey.compatibleDocumentTarget] as? NSNumber)?
                .uint32Value) == HwpCompatibleDocumentTarget.msWord.rawValue
        }

        /// MS 워드 호환 문서의 한 줄 끝(코드 10) run은 **라틴 슬롯** 글꼴이다 (#223) — 한글은 한
        /// 줄 끝을 문단 끝 글자처럼 글자 모양의 라틴 슬롯 글꼴로 줄 상자에 세운다 (한글 실측:
        /// 한글 슬롯 Apple SD·라틴 슬롯 함초롬돋움 10pt 글자 모양의 한글 글 뒤 한 줄 끝 줄
        /// `textheight` 2171 = 함초롬 상자 1692 + Apple SD 아래 몫 479). 라틴 50%(6pt)인 12pt
        /// 글자 모양으로 슬롯을 가른다 — 한글 문서는 종전대로 직전 run의 슬롯(한글 12pt)이다.
        func testMsWordLineBreakUsesTheLatinSlotFont() throws {
            let shapes: [UInt32: CoreHwp.HwpCharShape] = [
                0: try charShape(faceRelativeSize: [100, 50, 100, 100, 100, 100, 100]),
            ]
            func lineBreakSize(target: CoreHwp.HwpCompatibleDocumentTarget?) throws -> CGFloat {
                let built = builder(shapes: shapes, target: target)
                    .build(paragraph: paragraph(text: "가\u{0A}나\u{0D}", runs: [(0, 0)]))
                expect(built.attribute(
                    HwpAttributedStringKey.lineBreak, at: 1, effectiveRange: nil
                )).toNot(beNil())
                let value = try XCTUnwrap(built.attribute(
                    kCTFontAttributeName as NSAttributedString.Key, at: 1, effectiveRange: nil
                ))
                let ref = value as CFTypeRef
                try XCTSkipUnless(CFGetTypeID(ref) == CTFontGetTypeID(), "글꼴 없음")
                return CTFontGetSize(unsafeBitCast(ref, to: CTFont.self))
            }
            expect(try lineBreakSize(target: .msWord)).to(beCloseTo(6, within: 0.001))
            expect(try lineBreakSize(target: nil)).to(beCloseTo(12, within: 0.001))
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

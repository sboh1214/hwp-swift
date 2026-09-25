import CoreGraphics
@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 첨자(표 33)의 베이스라인 이동 계약 (#179) — `extension`에 두는 이유는
    /// `HwpTextRunBuilderTests` 본문이 `type_body_length` 경고선에 닿아 있어서다.
    ///
    /// 첨자 이동은 두 키에 실린다: 글리프를 옮기는 합산 키 `glyphBaselineOffset`(글자
    /// 위치 몫 포함)과 첨자 몫만 담는 `scriptBaselineOffset`. 장식선은 뒤 키만 본다 —
    /// 한글은 취소선·글자 가운데 밑줄을 첨자로 옮겨진 베이스라인에 그리되 글자
    /// 위치로 옮겨진 글리프는 따라가지 않으므로 (2026-09-15 실측) 합산 키로는 그릴
    /// 자리를 정할 수 없다.
    extension HwpTextRunBuilderTests {
        private static let superscriptBit: UInt32 = 1 << 15
        private static let subscriptBit: UInt32 = 1 << 16
        private static let strikethroughBit: UInt32 = 1 << 18
        /// 밑줄 종류 '글자 가운데' (bit 2~3 값 2)
        private static let centerUnderlineBits: UInt32 = 2 << 2

        /// 위 첨자 + 글자 위치 30: 합산 키는 두 몫의 합(5.28 − 3.6)이고 첨자 키는
        /// 첨자 몫(0.44 × 12pt)만이다.
        func testSuperscriptRecordsScriptShiftSeparatelyFromFaceLocation() throws {
            let paragraph = paragraph(text: "가", runs: [(0, 0)])
            let shape = try charShape(
                property: Self.superscriptBit, faceLocation: Array(repeating: 30, count: 7)
            )
            let attributes = builder(shapes: [0: shape])
                .build(paragraph: paragraph)
                .attributes(at: 0, effectiveRange: nil)

            let script = attributes[HwpAttributedStringKey.scriptBaselineOffset] as? NSNumber
            let glyph = attributes[HwpAttributedStringKey.glyphBaselineOffset] as? NSNumber
            expect(script?.doubleValue).to(beCloseTo(5.28, within: 0.0001))
            expect(glyph?.doubleValue).to(beCloseTo(5.28 - 3.6, within: 0.0001))
        }

        /// 아래 첨자는 음수 첨자 몫(−0.12 × 12pt)이고, 글자 위치 30(아래 3.6pt)과 합쳐
        /// 글리프는 5.04pt 내려간다.
        func testSubscriptRecordsNegativeScriptShift() throws {
            let paragraph = paragraph(text: "가", runs: [(0, 0)])
            let shape = try charShape(
                property: Self.subscriptBit, faceLocation: Array(repeating: 30, count: 7)
            )
            let attributes = builder(shapes: [0: shape])
                .build(paragraph: paragraph)
                .attributes(at: 0, effectiveRange: nil)

            let script = attributes[HwpAttributedStringKey.scriptBaselineOffset] as? NSNumber
            let glyph = attributes[HwpAttributedStringKey.glyphBaselineOffset] as? NSNumber
            expect(script?.doubleValue).to(beCloseTo(-1.44, within: 0.0001))
            expect(glyph?.doubleValue).to(beCloseTo(-5.04, within: 0.0001))
        }

        /// 글자 위치만 있는 run에는 첨자 키가 없다 — "첨자 run에만 키가 있다"가 이
        /// 키의 계약이라, 값 0짜리 키가 남으면 소비자가 첨자 run으로 오인한다(렌더러의
        /// 산술은 0과 없음을 같게 보지만 캐시·서식 복사 같은 다른 소비자는 다를 수 있다).
        func testFaceLocationAloneCarriesNoScriptShift() throws {
            let paragraph = paragraph(text: "가", runs: [(0, 0)])
            let shape = try charShape(faceLocation: Array(repeating: 30, count: 7))
            let attributes = builder(shapes: [0: shape])
                .build(paragraph: paragraph)
                .attributes(at: 0, effectiveRange: nil)

            expect(attributes[HwpAttributedStringKey.scriptBaselineOffset]).to(beNil())
            expect(attributes[HwpAttributedStringKey.glyphBaselineOffset]).toNot(beNil())
        }

        /// 첨자 없는 run에는 두 키 모두 없다.
        func testPlainRunCarriesNoScriptShift() throws {
            let paragraph = paragraph(text: "가", runs: [(0, 0)])
            let attributes = builder(shapes: [0: try charShape()])
                .build(paragraph: paragraph)
                .attributes(at: 0, effectiveRange: nil)

            expect(attributes[HwpAttributedStringKey.scriptBaselineOffset]).to(beNil())
            expect(attributes[HwpAttributedStringKey.glyphBaselineOffset]).to(beNil())
        }

        /// 첨자 run의 취소선·글자 가운데 밑줄은 취소선 키로 나가고 첨자 키와 함께
        /// 실린다 — 렌더러가 그 둘로 옮겨진 자리를 정한다. 두 장식이 같은 경로를
        /// 타므로 가운데 밑줄도 첨자를 따라간다.
        func testScriptRunKeepsStrikethroughAndCenterUnderlineWithScriptShift() throws {
            let paragraph = paragraph(text: "가나", runs: [(0, 0), (1, 1)])
            let strike = try charShape(property: Self.superscriptBit | Self.strikethroughBit)
            let center = try charShape(property: Self.subscriptBit | Self.centerUnderlineBits)
            let result = builder(shapes: [0: strike, 1: center]).build(paragraph: paragraph)

            for index in 0 ..< 2 {
                let attributes = result.attributes(at: index, effectiveRange: nil)
                expect(attributes[HwpAttributedStringKey.strikethroughStyle]).toNot(beNil())
                expect(attributes[HwpAttributedStringKey.scriptBaselineOffset]).toNot(beNil())
                // 밑줄 아래·위 키는 없다 — 가운데는 취소선으로 합류한 것이다.
                expect(attributes[HwpAttributedStringKey.underlineStyle]).to(beNil())
                expect(attributes[HwpAttributedStringKey.underlineAboveStyle]).to(beNil())
            }
            let first = result.attributes(at: 0, effectiveRange: nil)
            let second = result.attributes(at: 1, effectiveRange: nil)
            expect((first[HwpAttributedStringKey.scriptBaselineOffset] as? NSNumber)?.doubleValue)
                .to(beGreaterThan(0))
            expect((second[HwpAttributedStringKey.scriptBaselineOffset] as? NSNumber)?.doubleValue)
                .to(beLessThan(0))
        }

        /// 각주·미주 참조 번호(마커 치환 run)는 글자 모양 첨자와 **다른 규칙**이다 (#204, 한글
        /// 12.30 실측: 글꼴 0.75배·설정 크기의 0.21배 위) — 12pt 본문의 번호는 9pt 글꼴에
        /// 2.52pt 위이고, 글자 위치 30(아래 3.6)과 합치면 글리프는 1.08pt 아래다. 첨자 몫 키는
        /// 참조 번호에도 실려 장식선이 번호를 따라간다.
        func testNoteReferenceUsesItsOwnScaleAndShift() throws {
            var paragraph = paragraph(text: "가", runs: [(0, 0)])
            paragraph.paraText?.charArray.append(CoreHwp.HwpChar(type: .extended, value: 17))
            paragraph.ctrlHeaderArray = [
                .footnote(HwpSynthetic.listControl(ctrlId: .footnote, paragraphs: [])),
            ]
            let shape = try charShape(faceLocation: Array(repeating: 30, count: 7))
            let result = builder(shapes: [0: shape]).build(
                paragraph: paragraph,
                controlReplacements: [
                    0: HwpControlMarkerReplacement(text: "1)", isSuperscript: true),
                ]
            )
            expect(result.string) == "가1)"
            let attributes = result.attributes(at: 1, effectiveRange: nil)

            let script = attributes[HwpAttributedStringKey.scriptBaselineOffset] as? NSNumber
            let glyph = attributes[HwpAttributedStringKey.glyphBaselineOffset] as? NSNumber
            expect(script?.doubleValue).to(beCloseTo(2.52, within: 0.0001))
            expect(glyph?.doubleValue).to(beCloseTo(2.52 - 3.6, within: 0.0001))
            let fontValue = try XCTUnwrap(
                attributes[kCTFontAttributeName as NSAttributedString.Key]
            )
            let ref = fontValue as CFTypeRef
            expect(CFGetTypeID(ref)) == CTFontGetTypeID()
            let font = unsafeBitCast(ref, to: CTFont.self)
            expect(CTFontGetSize(font)).to(beCloseTo(9, within: 0.0001))
            // 글자 모양 첨자 규칙(0.64배·0.44em)으로 그리면 7.68pt·5.28 위라 갈린다.
            expect(HwpTextRunBuilder.noteReferenceScale) != HwpTextRunBuilder.superscriptScale
            expect(HwpTextRunBuilder.noteReferenceBaselineRatio)
                != HwpTextRunBuilder.superscriptBaselineRatio
            // 참조 번호는 첨자 축소 전 크기도 유지한다 — 장식선 두께·아래 밑줄 기준.
            let target = attributes[HwpAttributedStringKey.spaceTargetSize] as? NSNumber
            expect(target?.doubleValue).to(beCloseTo(12, within: 0.0001))
        }

        /// 상대 크기 50%의 위 첨자: 축소는 글꼴 크기(6pt)에, 올림은 설정 크기(12pt)에 건다 —
        /// 한글 20pt 상대 50% 위 첨자가 6.36pt 글리프로 8.88pt 위였다.
        func testSuperscriptScalesTheFontButShiftsBySettingSize() throws {
            let paragraph = paragraph(text: "가", runs: [(0, 0)])
            let shape = try charShape(
                property: Self.superscriptBit, faceRelativeSize: Array(repeating: 50, count: 7)
            )
            let attributes = builder(shapes: [0: shape])
                .build(paragraph: paragraph)
                .attributes(at: 0, effectiveRange: nil)

            let script = attributes[HwpAttributedStringKey.scriptBaselineOffset] as? NSNumber
            expect(script?.doubleValue).to(beCloseTo(12 * 0.44, within: 0.0001))
            let fontValue = try XCTUnwrap(
                attributes[kCTFontAttributeName as NSAttributedString.Key]
            )
            let ref = fontValue as CFTypeRef
            expect(CFGetTypeID(ref)) == CTFontGetTypeID()
            let font = unsafeBitCast(ref, to: CTFont.self)
            expect(CTFontGetSize(font)).to(beCloseTo(6 * 0.64, within: 0.0001))
        }

        /// 첨자 run도 `spaceTargetSize`는 축소 전 크기다 — 렌더러가 취소선의 첨자 축소 비율
        /// (run 글꼴 크기 ÷ 이 값), 기본 크기 키가 없는 문자열의 장식선 크기 폴백, 호환 문서 두
        /// 갈래의 선 모양 축척과 묶음 키(`sameLineShapeGroup`)로 쓴다 (한글은 첨자 run의 선도 본문
        /// 두께로 그린다; 한글 문서의 장식선 크기는 #226부터 `baseFontSize`다).
        func testScriptRunKeepsPreScriptSizeForDecorations() throws {
            let paragraph = paragraph(text: "가", runs: [(0, 0)])
            let shape = try charShape(property: Self.superscriptBit)
            let attributes = builder(shapes: [0: shape])
                .build(paragraph: paragraph)
                .attributes(at: 0, effectiveRange: nil)

            let target = attributes[HwpAttributedStringKey.spaceTargetSize] as? NSNumber
            expect(target?.doubleValue).to(beCloseTo(12, within: 0.0001))
            let fontValue = try XCTUnwrap(
                attributes[kCTFontAttributeName as NSAttributedString.Key]
            )
            let ref = fontValue as CFTypeRef
            expect(CFGetTypeID(ref)) == CTFontGetTypeID()
            let font = unsafeBitCast(ref, to: CTFont.self)
            expect(CTFontGetSize(font)).to(beCloseTo(12 * 0.64, within: 0.0001))
        }
    }
#endif

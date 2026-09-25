import CoreGraphics
@testable import CoreHwp
import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    /// 줄 단위 밑줄의 기준 (#226, `HwpDrawnTextLayout.underlineReference(of:endsParagraph:)`) —
    /// 한글 문서·한글 2007 호환 문서에서 밑줄 자리는 **줄 상자 높이**(세로 배치의 `vertsize`와
    /// 같은 값)가, 두께·선 모양 축척은 줄 **글자**의 기본 크기 최댓값이 정한다.
    ///
    /// 오라클은 한글.app 12.30.0 build 6446이 `CharShape` HWPX 기반 합성 문서(`hp:linesegarray`
    /// 제거)를 다시 조판한 PDF와 줄 캐시다 (2026-09-25, 함초롬바탕, 10pt 밑줄 run과 한 줄에 놓인
    /// 것 — 괄호는 캐시 `vertsize`와 PDF 밑줄 두께): 40pt 무장식 글자·공백 (4000, 1.56), 40pt 문단
    /// 끝 글자 (4000, 0.36), 40pt 한 줄 끝 (그 줄 4000·다음 줄 1000, 0.36), 40pt 글자 모양 책갈피
    /// (4000, 0.36), 10pt 마커의 40pt 그림 (4000, 0.36), 20pt 글자 + 40pt 문단 끝 글자 (4000,
    /// 0.84), 40pt 마커의 8pt 그림 + 20pt 글자 (2000, 0.84), 기본 40pt 위 첨자 무장식 run (4000,
    /// 1.56), 기본 10pt·상대 크기 200% (1000, 0.36). 입력은 Helvetica로 조판한다 — 한글 문서의
    /// 줄 상자는 글꼴 지표의 함수가 아니다.
    final class HwpUnderlineReferenceTests: XCTestCase {
        private typealias Fixtures = LineBoxFixtures

        private static func reference(
            _ string: NSAttributedString, endsParagraph: Bool = true
        ) -> HwpDecorationLineGeometry.UnderlineReference {
            HwpDrawnTextLayout.underlineReference(
                of: CTLineCreateWithAttributedString(string), endsParagraph: endsParagraph
            )
        }

        private static func concat(_ parts: [NSAttributedString]) -> NSAttributedString {
            let output = NSMutableAttributedString()
            parts.forEach(output.append)
            return output
        }

        private static func text(
            _ string: String, size: CGFloat, base: CGFloat? = nil
        ) -> NSAttributedString {
            NSAttributedString(
                string: string, attributes: Fixtures.attributes(size: size, baseSize: base)
            )
        }

        /// 문자열 전체에 문단 끝 글자(CR)의 기본 크기를 싣는다
        /// (`HwpTextRunBuilder.attachParagraphEndBaseFontSize`와 같은 꼴).
        private static func withParagraphEnd(
            _ size: CGFloat, _ string: NSAttributedString
        ) -> NSAttributedString {
            let output = NSMutableAttributedString(attributedString: string)
            output.addAttribute(
                HwpAttributedStringKey.paragraphEndBaseFontSize,
                value: NSNumber(value: Double(size)),
                range: NSRange(location: 0, length: output.length)
            )
            return output
        }

        /// 글자끼리는 가장 큰 글자가 줄 상자와 두께를 함께 정한다 — 무장식 글자·공백도 후보다.
        func testTheLargestTextSetsBothTheBoxAndTheThickness() {
            for tail in ["big", "  "] {
                let reference = Self.reference(Self.concat([
                    Self.text("ab", size: 10), Self.text(tail, size: 40),
                ]))
                expect(reference.lineBoxHeight).to(equal(40), description: "'\(tail)'")
                expect(reference.textFontSize).to(equal(40), description: "'\(tail)'")
                expect(reference.msWordLineBox).to(beNil())
            }
            let single = Self.reference(Self.text("ab", size: 10))
            expect(single.lineBoxHeight) == 10
            expect(single.textFontSize) == 10
        }

        /// 문단 끝 글자(CR)는 **문단의 마지막 줄**의 상자에만 들고 두께에는 들지 않는다 — 20pt 글과
        /// 40pt CR 줄은 상자 40·두께 기준 20이다.
        func testParagraphEndCharacterJoinsOnlyTheBoxOfTheLastLine() {
            let string = Self.withParagraphEnd(40, Self.concat([
                Self.text("ab", size: 20), Self.text("cd", size: 10),
            ]))
            let last = Self.reference(string, endsParagraph: true)
            expect(last.lineBoxHeight) == 40
            expect(last.textFontSize) == 20
            let continued = Self.reference(string, endsParagraph: false)
            expect(continued.lineBoxHeight) == 20
            expect(continued.textFontSize) == 20
        }

        /// 한 줄 끝(코드 10)·높이 0 마커(책갈피)·개체 마커는 상자에는 들 수 있어도 두께 기준에는
        /// 들지 않는다 — 넷 다 40pt인 줄의 10pt 밑줄은 상자 40·두께 기준 10이다 (개체 마커는 자기
        /// 글자 모양 대신 개체 높이로 상자에 든다, #217).
        func testLineBreakMarkersAndObjectsStayOutOfTheThickness() {
            let body = Self.text("ab", size: 10)
            let big = Fixtures.attributes(size: 40)
            let cases: [(String, NSAttributedString)] = [
                ("한 줄 끝", Self.concat([body, Fixtures.lineBreak(attributes: big)])),
                ("책갈피", Self.concat([body, Fixtures.objectMarker(height: 0, attributes: big)])),
                ("개체", Self.concat([
                    body,
                    Fixtures.objectMarker(height: 40, attributes: Fixtures.attributes(size: 10)),
                ])),
                ("40pt 마커 개체", Self.concat([
                    body, Fixtures.objectMarker(height: 40, attributes: big),
                ])),
            ]
            for (name, string) in cases {
                let reference = Self.reference(string, endsParagraph: false)
                expect(reference.lineBoxHeight).to(equal(40), description: name)
                expect(reference.textFontSize).to(equal(10), description: name)
            }
            // 40pt 글자 모양 마커의 8pt 그림 + 20pt 글자: 상자 20·두께 기준 20 (한글 2000·0.84).
            let marked = Self.reference(Self.concat([
                body, Fixtures.objectMarker(height: 8, attributes: big), Self.text("cd", size: 20),
            ]), endsParagraph: false)
            expect(marked.lineBoxHeight) == 20
            expect(marked.textFontSize) == 20
        }

        /// 빈 줄 앵커와 결합 문자열의 문단 구분자는 조판 문자열에만 있는 글자라 두께 기준에서
        /// 빠진다 — 문단 끝 글자의 자리이기 때문이다.
        func testSyntheticEndStandInsStayOutOfTheThickness() {
            let big = Fixtures.attributes(size: 40)
            var separator = big
            separator[HwpAttributedStringKey.combinedParagraphSeparator] = NSNumber(value: true)
            let cases: [(String, NSAttributedString)] = [
                ("빈 줄 앵커", Self.concat([
                    Self.text("ab", size: 10), Fixtures.emptyLineAnchor(attributes: big),
                ])),
                ("결합 문자열 구분자", Self.concat([
                    Self.text("ab", size: 10),
                    NSAttributedString(string: "\n", attributes: separator),
                ])),
            ]
            for (name, string) in cases {
                expect(Self.reference(string, endsParagraph: false).textFontSize)
                    .to(equal(10), description: name)
            }
        }

        /// 크기는 **글자 모양 기본 크기**다 — 상대 크기로 20pt가 된 기본 40pt run은 상자·두께 모두
        /// 40, 200%로 20pt가 된 기본 10pt run은 10이다 (한글: −6.84·1.56 / −1.68·0.36).
        func testRelativeSizeDoesNotChangeTheReference() {
            let shrunk = Self.reference(Self.text("ab", size: 20, base: 40))
            expect(shrunk.lineBoxHeight) == 40
            expect(shrunk.textFontSize) == 40
            let grown = Self.reference(Self.text("ab", size: 20, base: 10))
            expect(grown.lineBoxHeight) == 10
            expect(grown.textFontSize) == 10
        }

        /// 첨자 run은 **축소 전 기본 크기**로 줄 상자와 두께 기준에 든다 — 기본 40pt 위 첨자 무장식
        /// run(글꼴 25.6pt)과 한 줄인 10pt 밑줄은 40pt 상자·40pt 두께다 (한글 12.30: −6.72·1.56).
        /// 줄어든 글꼴 크기로 들면 상자·두께 기준이 25.6pt가 된다.
        func testSuperscriptRunJoinsWithItsBaseSize() {
            let reference = Self.reference(Self.concat([
                Self.text("ab", size: 10), Self.text("sup", size: 40 * 0.64, base: 40),
            ]), endsParagraph: false)
            expect(reference.lineBoxHeight) == 40
            expect(reference.textFontSize) == 40
        }

        /// 기본 크기 표식이 없는 합성 문자열은 조판 글꼴 크기로 떨어진다 (공개 `drawText` 입력).
        func testUnmarkedStringFallsBackToTheFontSize() {
            let string = NSAttributedString(
                string: "ab", attributes: Fixtures.fontOnlyAttributes(size: 16)
            )
            let reference = Self.reference(string)
            expect(reference.lineBoxHeight) == 16
            expect(reference.textFontSize) == 16
        }

        /// MS 워드 호환 문서 줄은 글꼴 줄 상자를 싣는다 — `msWordLineBox(of:endsParagraph:)`와
        /// 같은 값이라 밑줄이 세로 배치와 같은 상자에서 나온다 (#187·#223).
        func testMsWordLineCarriesItsFontLineBox() {
            var attributes = Fixtures.attributes(size: 10, fontName: "Menlo")
            attributes[HwpAttributedStringKey.compatibleDocumentTarget] = NSNumber(
                value: HwpCompatibleDocumentTarget.msWord.rawValue
            )
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: "ab", attributes: attributes)
            )
            let reference = HwpDrawnTextLayout.underlineReference(of: line, endsParagraph: false)
            expect(reference.msWordLineBox).toNot(beNil())
            expect(reference.msWordLineBox) == HwpDrawnTextLayout.msWordLineBox(
                of: line, endsParagraph: false
            )
        }
    }
#endif

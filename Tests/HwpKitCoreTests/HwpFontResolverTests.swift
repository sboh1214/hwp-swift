import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpFontResolverTests: XCTestCase {
        let resolver = HwpFontResolver()

        /// 미분류 스크립트는 영문 슬롯이 아니라 소속 슬롯으로 (R33 #2) —
        /// 아랍/히브리는 '기타 언어', 확장 자모는 한글, 호환 한자는 한자.
        func testScriptDetectionRoutesNonLatinScripts() throws {
            expect(HwpScript.detect(from: try XCTUnwrap("م".unicodeScalars.first))) == .etc
            expect(HwpScript.detect(from: try XCTUnwrap("א".unicodeScalars.first))) == .etc
            expect(HwpScript.detect(from: try XCTUnwrap("ไ".unicodeScalars.first))) == .etc
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0x0870)))) == .etc
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0xA960)))) == .korean
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0xD7B0)))) == .korean
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0xF900)))) == .chinese
            expect(HwpScript.detect(from: try XCTUnwrap("A".unicodeScalars.first))) == .english
        }

        /// 사설 영역(보충 플레인 포함)은 사용자 슬롯, 반각 가타카나는 일문,
        /// 기하 도형·딩뱃은 기호, 벵골~타밀은 '기타 언어' 슬롯이다 (R35 #3·#5).
        func testScriptDetectionRoutesUserSymbolJapaneseAndIndicScripts() throws {
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0xE000)))) == .user
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0xF0000)))) == .user
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0x100000)))) == .user
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0xFF66)))) == .japanese
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0x2500)))) == .symbol
            expect(HwpScript.detect(from: try XCTUnwrap(Unicode.Scalar(0x25A1)))) == .english
            expect(HwpScript.detect(from: try XCTUnwrap("অ".unicodeScalars.first))) == .etc
            expect(HwpScript.detect(from: try XCTUnwrap("த".unicodeScalars.first))) == .etc
        }

        func testUnknownFontFallback() {
            let font = resolver.resolve(faceName: "unknown-font-xyz", script: .korean, size: 12)
            expect(CTFontGetSize(font)) == 12.0
        }

        func testKnownSystemFontResolution() {
            let font = resolver.resolve(faceName: "Menlo", script: .english, size: 14)
            expect(CTFontCopyFamilyName(font) as String) == "Menlo"
        }

        func testCustomFontMapOverride() {
            let customMap = HwpFontMap(entries: ["MyFont": ["Menlo"]])
            let customResolver = HwpFontResolver(fontMap: customMap)
            let font = customResolver.resolve(faceName: "MyFont", script: .english, size: 12)
            expect(CTFontCopyFamilyName(font) as String) == "Menlo"
        }

        func testDeterministicResolverReturnsMenlo() {
            let font = HwpFontResolver.testDeterministic.resolve(
                faceName: "unknown-font-xyz", script: .korean, size: 12
            )
            expect(CTFontCopyFamilyName(font) as String) == "Menlo"
        }

        func testDefaultFontMapEntryCount() {
            expect(HwpFontMap.default.entries.count) >= 15
        }

        func testSerifFacesResolveToMyungjoFamily() {
            // 헌법주석 서체 (명조 계열): 고딕 last-resort로 떨어지면 안 된다.
            // 한컴오피스가 설치된 기기에서는 원문 이름의 실폰트가 우선한다.
            let serifFaces = [
                "휴먼명조", "한양신명조", "한양신명조V", "신명 태명조", "#태명조",
                "명조", "신명 견명조", "신명조 간자", "신명조 약자",
            ]
            let serifFamilies = ["AppleMyungjo", "Nanum Myeongjo", "HCR Batang"]
            for face in serifFaces {
                let font = resolver.resolve(faceName: face, script: .korean, size: 10)
                let family = CTFontCopyFamilyName(font) as String
                if isInstalledHancomFont(family) {
                    continue
                }
                expect(serifFamilies).to(
                    contain(family),
                    description: "'\(face)'이 명조 계열로 해석되지 않았다: \(family)"
                )
            }
        }

        func testGothicFacesResolveToGothicFamily() {
            let gothicFaces = ["한양중고딕", "신명 중고딕", "#중고딕", "-윤고딕120", "신명 디나루"]
            let gothicFamilies = ["Apple SD Gothic Neo", "Nanum Gothic"]
            for face in gothicFaces {
                let font = resolver.resolve(faceName: face, script: .korean, size: 10)
                let family = CTFontCopyFamilyName(font) as String
                if isInstalledHancomFont(family) {
                    continue
                }
                expect(gothicFamilies).to(
                    contain(family),
                    description: "'\(face)'이 고딕 계열로 해석되지 않았다: \(family)"
                )
            }
        }

        func testHancomBatangResolvesToBatangFamily() {
            let batangFamilies = ["HCR Batang", "Nanum Myeongjo", "AppleMyungjo"]
            for face in ["한컴바탕", "한컴바탕확장", "바탕체"] {
                let font = resolver.resolve(faceName: face, script: .korean, size: 10)
                let family = CTFontCopyFamilyName(font) as String
                if isInstalledHancomFont(family) {
                    continue
                }
                expect(batangFamilies).to(
                    contain(family),
                    description: "'\(face)'이 바탕 계열로 해석되지 않았다: \(family)"
                )
            }
        }

        func testCalligraphicFaceResolvesToGungSeo() {
            let font = resolver.resolve(faceName: "한양해서", script: .korean, size: 10)
            let family = CTFontCopyFamilyName(font) as String
            if isInstalledHancomFont(family) {
                return
            }
            expect(["GungSeo", "AppleMyungjo"]).to(contain(family))
        }

        /// 해석 결과가 한컴오피스 번들 실폰트인지 (설치된 기기에서는 실폰트가
        /// 폴백 계열보다 우선하므로 폴백 계열 검사를 건너뛴다)
        private func isInstalledHancomFont(_ family: String) -> Bool {
            HwpInstalledHancomFonts.index[family] != nil
                || HwpInstalledHancomFonts.index[HwpFontMap.normalize(family)] != nil
        }

        func testFaceNameNormalizationStripsPrefixesAndSpaces() {
            expect(HwpFontMap.normalize("-윤고딕120")) == "윤고딕120"
            expect(HwpFontMap.normalize("#태명조")) == "태명조"
            expect(HwpFontMap.normalize("신명 태명조")) == "신명태명조"
            expect(HwpFontMap.default.candidates(forFaceName: "#중고딕")).notTo(beEmpty())
            expect(HwpFontMap.default.candidates(forFaceName: "신명 디나루")).notTo(beEmpty())
            expect(HwpFontMap.default.candidates(forFaceName: "미지의서체")).to(beEmpty())
        }
    }
#endif

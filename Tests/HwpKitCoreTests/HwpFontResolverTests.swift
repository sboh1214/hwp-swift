import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpFontResolverTests: XCTestCase {
        let resolver = HwpFontResolver()

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
            // 헌법주석 서체 (명조 계열): 고딕 last-resort로 떨어지면 안 된다
            let serifFaces = [
                "휴먼명조", "한양신명조", "한양신명조V", "신명 태명조", "#태명조",
                "명조", "신명 견명조", "신명조 간자", "신명조 약자",
            ]
            let serifFamilies = ["AppleMyungjo", "Nanum Myeongjo", "HCR Batang"]
            for face in serifFaces {
                let font = resolver.resolve(faceName: face, script: .korean, size: 10)
                let family = CTFontCopyFamilyName(font) as String
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
                expect(batangFamilies).to(
                    contain(family),
                    description: "'\(face)'이 바탕 계열로 해석되지 않았다: \(family)"
                )
            }
        }

        func testCalligraphicFaceResolvesToGungSeo() {
            let font = resolver.resolve(faceName: "한양해서", script: .korean, size: 10)
            let family = CTFontCopyFamilyName(font) as String
            expect(["GungSeo", "AppleMyungjo"]).to(contain(family))
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

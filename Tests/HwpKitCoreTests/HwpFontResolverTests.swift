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
    }
#endif

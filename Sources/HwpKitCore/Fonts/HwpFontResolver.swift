import CoreGraphics
import Foundation

#if canImport(CoreText)
    import CoreText

    /// Resolves HWP face names to CTFont instances via a fallback map.
    /// All CTFont creation is centralized here — no fallback chains elsewhere.
    public struct HwpFontResolver: Sendable {
        private let fontMap: HwpFontMap
        private let availableFamilies: Set<String>
        private let scriptFallbacks: [HwpScript: String]

        private static let defaultScriptFallbacks: [HwpScript: String] = [
            .korean: "Apple SD Gothic Neo",
            .english: "Helvetica",
            .chinese: "Apple SD Gothic Neo",
            .japanese: "Apple SD Gothic Neo",
            .etc: "Helvetica",
            .symbol: "Symbol",
            .user: "Helvetica",
        ]

        public init(fontMap: HwpFontMap = .default) {
            self.fontMap = fontMap
            scriptFallbacks = Self.defaultScriptFallbacks
            let nsArray = CTFontManagerCopyAvailableFontFamilyNames() as NSArray
            availableFamilies = Set(nsArray.compactMap { $0 as? String })
        }

        private init(fontMap: HwpFontMap, scriptFallbacks: [HwpScript: String]) {
            self.fontMap = fontMap
            self.scriptFallbacks = scriptFallbacks
            let nsArray = CTFontManagerCopyAvailableFontFamilyNames() as NSArray
            availableFamilies = Set(nsArray.compactMap { $0 as? String })
        }

        /// Resolves `faceName` for `script` at `size` points.
        /// Walks map candidates then the face name itself; falls back to script-keyed safety net.
        public func resolve(faceName: String, script: HwpScript, size: CGFloat) -> CTFont {
            let candidates = (fontMap.entries[faceName] ?? []) + [faceName]
            for candidate in candidates {
                if availableFamilies.contains(candidate) {
                    return CTFontCreateWithName(candidate as CFString, size, nil)
                }
            }
            let fallbackName = scriptFallbacks[script] ?? "Helvetica"
            return CTFontCreateWithName(fallbackName as CFString, size, nil)
        }

        /// A resolver whose script fallbacks all resolve to "Menlo" for deterministic snapshot tests.
        public static let testDeterministic: HwpFontResolver = .init(
            fontMap: HwpFontMap(entries: [:]),
            scriptFallbacks: [
                .korean: "Menlo",
                .english: "Menlo",
                .chinese: "Menlo",
                .japanese: "Menlo",
                .etc: "Menlo",
                .symbol: "Menlo",
                .user: "Menlo",
            ]
        )
    }
#endif

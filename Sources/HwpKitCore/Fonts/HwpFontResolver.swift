import CoreGraphics
import Foundation

#if canImport(CoreText)
    import CoreText

    /// Resolves HWP face names to CTFont instances via a fallback map.
    /// All CTFont creation is centralized here — no fallback chains elsewhere.
    public struct HwpFontResolver: Sendable {
        private let fontMap: HwpFontMap
        private let scriptFallbacks: [HwpScript: String]
        private let cache = FontCache()

        private struct CacheKey: Hashable {
            let faceName: String
            let script: HwpScript
            let size: CGFloat
        }

        /// CTFont is immutable and thread-safe; access to the dictionary is lock-guarded.
        private final class FontCache: @unchecked Sendable {
            private var storage: [CacheKey: CTFont] = [:]
            private let lock = NSLock()

            func font(for key: CacheKey, create: () -> CTFont) -> CTFont {
                lock.lock()
                if let cached = storage[key] {
                    lock.unlock()
                    return cached
                }
                lock.unlock()
                let font = create()
                lock.lock()
                storage[key] = font
                lock.unlock()
                return font
            }
        }

        private static let defaultScriptFallbacks: [HwpScript: String] = [
            .korean: "Apple SD Gothic Neo",
            .english: "Helvetica",
            .chinese: "Apple SD Gothic Neo",
            .japanese: "Apple SD Gothic Neo",
            .etc: "Helvetica",
            .symbol: "Symbol",
            .user: "Helvetica",
        ]

        /// 한컴오피스 번들 폰트 (설치 시)를 조회 대상에 넣을지.
        /// 결정론 테스트 resolver는 끈다 (기기 의존 결과 방지).
        private let usesInstalledHancomFonts: Bool

        public init(fontMap: HwpFontMap = .default) {
            self.fontMap = fontMap
            scriptFallbacks = Self.defaultScriptFallbacks
            usesInstalledHancomFonts = true
        }

        private init(
            fontMap: HwpFontMap,
            scriptFallbacks: [HwpScript: String],
            usesInstalledHancomFonts: Bool = true
        ) {
            self.fontMap = fontMap
            self.scriptFallbacks = scriptFallbacks
            self.usesInstalledHancomFonts = usesInstalledHancomFonts
        }

        /// Resolves `faceName` for `script` at `size` points.
        /// 원문 이름의 실제 폰트 (시스템 → 한컴오피스 번들)를 먼저 찾고,
        /// 없을 때만 map 폴백 후보 (원문 → 정규화 이름 조회) →
        /// script-keyed safety net 순으로 내려간다.
        public func resolve(faceName: String, script: HwpScript, size: CGFloat) -> CTFont {
            cache.font(for: CacheKey(faceName: faceName, script: script, size: size)) {
                for candidate in [faceName] + fontMap.candidates(forFaceName: faceName) {
                    if let font = Self.createIfAvailable(name: candidate, size: size) {
                        return font
                    }
                    if usesInstalledHancomFonts,
                       let descriptor = HwpInstalledHancomFonts.descriptor(
                           forFaceName: candidate
                       )
                    {
                        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
                    }
                }
                let fallbackName = scriptFallbacks[script] ?? "Helvetica"
                return CTFontCreateWithName(fallbackName as CFString, size, nil)
            }
        }

        private static func createIfAvailable(name: String, size: CGFloat) -> CTFont? {
            if let font = matchDescriptor(
                name: name,
                attribute: kCTFontFamilyNameAttribute,
                size: size
            ) {
                return font
            }
            return matchDescriptor(name: name, attribute: kCTFontNameAttribute, size: size)
        }

        private static func matchDescriptor(
            name: String,
            attribute: CFString,
            size: CGFloat
        ) -> CTFont? {
            let attrs = [attribute: name as CFString] as CFDictionary
            let descriptor = CTFontDescriptorCreateWithAttributes(attrs)
            let requiredAttributes = Set([attribute]) as NSSet as CFSet
            let matchedDescriptor = CTFontDescriptorCreateMatchingFontDescriptor(
                descriptor,
                requiredAttributes
            )
            guard let matched = matchedDescriptor,
                  let matchedName = CTFontDescriptorCopyAttribute(matched, attribute) as? String,
                  matchedName == name
            else { return nil }
            return CTFontCreateWithFontDescriptor(matched, size, nil)
        }

        /// A resolver whose script fallbacks all resolve to "Menlo"
        /// for deterministic snapshot tests.
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
            ],
            usesInstalledHancomFonts: false
        )
    }
#endif

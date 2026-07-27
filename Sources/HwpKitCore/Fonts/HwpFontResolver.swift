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

        /// - Parameter usesInstalledHancomFonts: 한컴오피스 앱 번들의 폰트를 조회
        ///   대상에 넣을지. 기본값은 `HwpInstalledHancomFonts.isEnabled`
        ///   (환경변수 `HWP_HANCOM_FONTS`, 미설정 시 off) — 번들에 타 파운드리
        ///   라이선스 폰트가 섞여 있어 배포 기본값을 off로 둔다. `true`를 명시하면
        ///   환경변수와 무관하게 켜진다.
        public init(
            fontMap: HwpFontMap = .default,
            usesInstalledHancomFonts: Bool = HwpInstalledHancomFonts.isEnabled
        ) {
            self.fontMap = fontMap
            scriptFallbacks = Self.defaultScriptFallbacks
            self.usesInstalledHancomFonts = usesInstalledHancomFonts
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

        /// 시스템에 등록된 폰트 이름 (family ∪ PostScript). 프로세스당 1회 만든다.
        /// matchDescriptor는 `matchedName == name`일 때만 성공하므로 이 집합에
        /// 없는 이름은 반드시 nil이다 — 먼저 걸러도 결과가 같고, 부재 이름마다
        /// CoreText 매칭을 호출하는 비용이 사라진다. 한컴 번들 폰트는 등록하지
        /// 않고 파일 descriptor로 따로 조회하므로 이 집합과 무관하다.
        private static let registeredFontNames: Set<String> = {
            var names = Set<String>()
            if let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] {
                names.formUnion(families)
            }
            if let postScriptNames = CTFontManagerCopyAvailablePostScriptNames() as? [String] {
                names.formUnion(postScriptNames)
            }
            return names
        }()

        private static func createIfAvailable(name: String, size: CGFloat) -> CTFont? {
            guard registeredFontNames.contains(name) else { return nil }
            if let font = matchDescriptor(
                name: name,
                attribute: kCTFontFamilyNameAttribute,
                size: size
            ) {
                return font
            }
            return matchDescriptor(name: name, attribute: kCTFontNameAttribute, size: size)
        }

        /// 비싼 CoreText 매칭 호출 횟수 — 부재 이름을 걸러 내는 상한회로가
        /// 실제로 호출을 없애는지 테스트가 관측한다 (overrideMaximumPages와 같은
        /// 테스트 전용 관측 지점).
        static let matchCounter = MatchCounter()

        final class MatchCounter: @unchecked Sendable {
            private var value = 0
            private let lock = NSLock()

            var count: Int {
                lock.lock()
                defer { lock.unlock() }
                return value
            }

            func increment() {
                lock.lock()
                value += 1
                lock.unlock()
            }

            func reset() {
                lock.lock()
                value = 0
                lock.unlock()
            }
        }

        private static func matchDescriptor(
            name: String,
            attribute: CFString,
            size: CGFloat
        ) -> CTFont? {
            matchCounter.increment()
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

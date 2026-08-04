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
            /// 문서가 선언한 대체/기반 글꼴명 — 같은 faceName이라도 문서마다 다를
            /// 수 있어 키에 포함해야 resolver를 재사용할 때 오염되지 않는다.
            let alternatives: [String]
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

        /// 한컴 번들 폰트를 조회 대상에 넣는지. `serifLatinFallback` 처럼 resolver
        /// 밖에서 같은 판단을 해야 하는 곳이 참조한다 — 그쪽이 이 값을 무시하고
        /// 인덱스를 직접 보면 opt-in 이 뚫린다.
        public let usesInstalledHancomFonts: Bool

        /// 문서가 선언한 대체/기반 글꼴 (`resolve`의 `alternatives`)을 후보로 쓸지.
        /// 결정론 resolver (`testDeterministic`)만 끈다 — 대체명은 실제 설치된 폰트를
        /// 가리키는 일이 많아 (기본 문서의 `함초롬바탕`이 `defaultFaceName`에
        /// "HCR Batang"을 적어 둔다) 켜 두면 그 폰트 설치 여부로 조판이 갈린다.
        private let usesDocumentAlternatives: Bool

        /// 시스템에 등록된 폰트를 후보 조회 대상에 넣을지. 결정론 resolver
        /// (`testDeterministic`)만 끈다 — HWP 원문 face 이름은 그 자체가 **시스템
        /// 폰트명일 수 있어** (`굴림`·`바탕`은 MS Office가, `함초롬바탕`은 한글
        /// 정식 설치가 같은 한글 이름으로 등록한다) 이 축이 열려 있으면 같은 문서가
        /// 기여자 머신마다 다른 실폰트로 조판된다. 한컴 번들·문서 대체 글꼴 축을
        /// 닫아도 이 축 하나로 결정론이 깨지므로, 커밋 가능한 골든 기준선을 뜨려면
        /// 셋을 모두 닫아야 한다.
        private let usesSystemFontLookup: Bool

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
            usesDocumentAlternatives = true
            usesSystemFontLookup = true
            // 배포 경로는 시스템 기본 대체를 그대로 쓴다 — 사용자 기기의 폰트로
            // 최대한 그리는 것이 맞고, 고정은 결정론 테스트 전용이다.
            fallbackCascade = []
        }

        /// 기본값을 두지 않는다 — public init의 기본값은 off (환경변수)인데 여기만
        /// `= true`로 남으면 읽는 쪽이 기본 동작을 반대로 이해한다.
        private init(
            fontMap: HwpFontMap,
            scriptFallbacks: [HwpScript: String],
            usesInstalledHancomFonts: Bool,
            usesDocumentAlternatives: Bool,
            usesSystemFontLookup: Bool,
            fallbackCascade: [String] = []
        ) {
            self.fontMap = fontMap
            self.scriptFallbacks = scriptFallbacks
            self.usesInstalledHancomFonts = usesInstalledHancomFonts
            self.usesDocumentAlternatives = usesDocumentAlternatives
            self.usesSystemFontLookup = usesSystemFontLookup
            self.fallbackCascade = fallbackCascade
        }

        /// 폴백 폰트가 **못 가진 글자**를 CoreText가 어떤 폰트로 대체할지 고정하는
        /// 목록. 비어 있으면 시스템 기본 대체 (배포 동작)다.
        ///
        /// 결정론 resolver의 마지막 구멍이 여기였다: 폰트 조회 세 축을 닫아 모든
        /// face를 Menlo로 보내도, Menlo가 못 가진 글자마다 CoreText가 **호스트에
        /// 설치된 폰트 목록**을 걸어가 대체한다. 헌법주석 코퍼스는 2,054자 중
        /// 1,929자(94%)가 Menlo 밖이라 사실상 조판 전체가 호스트 종속이었다 —
        /// 로마숫자 `Ⅵ`(U+2165)가 이 머신에선 Helvetica-Oblique로, CI 러너에선
        /// 다른 폰트로 잡혀 각주 줄 높이가 갈렸다 (블록 스냅샷 CI 실패의 원인).
        /// 목록을 명시하면 그 선택이 (base, cascade)의 함수가 되어 러너와 무관해진다.
        private let fallbackCascade: [String]

        /// 캐스케이드가 비면 시스템 기본 대체, 아니면 그 목록으로 **대체까지 고정**.
        private static func createFont(
            name: String, size: CGFloat, cascade: [String]
        ) -> CTFont {
            guard !cascade.isEmpty else {
                return CTFontCreateWithName(name as CFString, size, nil)
            }
            let descriptors = cascade.map { fallback in
                CTFontDescriptorCreateWithAttributes(
                    [kCTFontNameAttribute: fallback as CFString] as CFDictionary
                )
            }
            let descriptor = CTFontDescriptorCreateWithAttributes([
                kCTFontNameAttribute: name as CFString,
                kCTFontCascadeListAttribute: descriptors as CFArray,
            ] as CFDictionary)
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }

        /// Resolves `faceName` for `script` at `size` points.
        /// 원문 이름의 실제 폰트 (시스템 → 한컴오피스 번들)를 먼저 찾고,
        /// 없을 때만 map 폴백 후보 (원문 → 정규화 이름 조회) →
        /// script-keyed safety net 순으로 내려간다.
        ///
        /// - Parameter alternatives: 문서가 `HwpFaceName`에 적어 둔 대체 글꼴
        ///   (`alternativeFaceName`)·기반 글꼴 (`defaultFaceName`) 이름. 큐레이션한
        ///   `fontMap`을 **다 쓴 뒤** script 폴백 직전에 시도한다 — 맵에 있는 face는
        ///   검증된 기존 해석을 유지하고, 맵에 없는 face만 문서가 알려준 이름으로
        ///   구제된다 (맵은 ~50개인데 실제 문서의 face는 그보다 훨씬 많다).
        ///   각 이름은 그 자체로 다시 map을 거친다 — 대체명도 HWP face 이름이라
        ///   ("Myeongjo"의 대체는 "명조") 시스템 폰트명이 아니기 때문이다.
        public func resolve(
            faceName: String,
            alternatives: [String] = [],
            script: HwpScript,
            size: CGFloat
        ) -> CTFont {
            let key = CacheKey(
                faceName: faceName, alternatives: alternatives, script: script, size: size
            )
            return cache.font(for: key) {
                var candidates = [faceName] + fontMap.candidates(forFaceName: faceName)
                if usesDocumentAlternatives {
                    for alternative in alternatives where !alternative.isEmpty {
                        candidates.append(alternative)
                        candidates.append(contentsOf: fontMap.candidates(forFaceName: alternative))
                    }
                }
                for candidate in candidates {
                    if usesSystemFontLookup,
                       let font = Self.createIfAvailable(name: candidate, size: size)
                    {
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
                return Self.createFont(
                    name: fallbackName, size: size, cascade: fallbackCascade
                )
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

        /// 모든 face를 "Menlo"로 해석하는 기기 독립 resolver — 커밋 가능한 골든
        /// 기준선용. 폰트 조회의 **네 축**을 모두 닫아 어떤 폰트가 설치된 기기에서도
        /// 같은 CTFont가 나온다: 시스템 등록 폰트·한컴 번들·문서 대체 글꼴, 그리고
        /// Menlo가 못 가진 글자의 **대체 폰트** (`fallbackCascade` →
        /// `kCTFontCascadeListAttribute`).
        ///
        /// 넷째 축을 열어 두면 CoreText가 **호스트에 설치된 폰트 목록**에서 골라
        /// 기기마다 갈린다 — 헌법주석은 2,054자 중 1,929자 (94%) 가 Menlo 밖이라
        /// 조판 전체가 그 선택에 달려 있었다 (#95). 빈 캐스케이드는 CoreText가
        /// 무시하므로 목록을 명시해야 닫힌다.
        ///
        /// 남는 잔차는 캐스케이드의 폰트들에도 없는 글자뿐이다. 이 resolver를 쓰는
        /// 기준선은 임계를 여유 있게 잡거나 양자화를 거칠게 해 그것을 흡수한다.
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
            usesInstalledHancomFonts: false,
            usesDocumentAlternatives: false,
            usesSystemFontLookup: false,
            // Menlo 밖 글자의 대체를 고정한다 — 셋 다 macOS·iOS에 기본 탑재라
            // 러너에 무엇이 설치돼 있든 같은 폰트가 나온다. 한글·로마숫자·기호는
            // Apple SD Gothic Neo가, 일본 신자체 한자는 Hiragino Sans가 받는다.
            fallbackCascade: ["Apple SD Gothic Neo", "Hiragino Sans", "Apple Symbols"]
        )
    }
#endif

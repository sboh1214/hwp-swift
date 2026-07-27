import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    final class HwpFontResolverTests: XCTestCase {
        let resolver = HwpFontResolver()

        /// 시스템에 없는 이름은 비싼 CoreText 매칭을 호출하지 않는다 — 매칭 성공
        /// 조건이 `matchedName == name`이라 등록되지 않은 이름은 반드시 nil이므로
        /// 미리 걸러도 결과가 같다. 크기마다 다시 조회하면 폰트가 전부 부재한
        /// 환경(CI)에서 호출이 배로 늘어난다.
        func testAbsentFaceNameSkipsExpensiveMatching() {
            HwpFontResolver.matchCounter.reset()

            for size in [CGFloat(9), 10, 11, 12, 14] {
                _ = resolver.resolve(faceName: "ZzNoSuchFaceXYZ", script: .korean, size: size)
            }

            expect(HwpFontResolver.matchCounter.count) == 0
        }

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

        /// 폴백 후보는 createIfAvailable의 정확 일치 매칭이 해석할 수 있는
        /// 이름이어야 한다 — "AppleSDGothicNeo"는 family도 완전한 PostScript명도
        /// 아니라 항상 스킵된다 (R37 #2).
        func testFontMapUsesResolvableAppleSDGothicFamilyName() {
            let candidates = HwpFontMap.default.entries.values.flatMap { $0 }
            expect(candidates).toNot(contain("AppleSDGothicNeo"))
            expect(candidates).to(contain("Apple SD Gothic Neo"))
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
            let serifFamilies = expectedFamilies(
                preferring: ["AppleMyungjo", "Nanum Myeongjo", "HCR Batang"]
            )
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

        /// 확장 페이스(`한컴바탕확장`)는 여기서 제외한다 — 이름만 바탕이지 한자용
        /// 송체이고, 문서가 `defaultFaceName`에 FZSong_Superfont를 적어 둔다
        /// (`testBatangExtensionMapsToCJKSong`).
        func testHancomBatangResolvesToBatangFamily() {
            let batangFamilies = expectedFamilies(
                preferring: ["HCR Batang", "Nanum Myeongjo", "AppleMyungjo"]
            )
            for face in ["한컴바탕", "바탕체"] {
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
            let calligraphicFamilies = expectedFamilies(preferring: ["GungSeo", "AppleMyungjo"])
            expect(calligraphicFamilies).to(contain(family))
        }

        /// 해석 결과가 한컴오피스 번들 실폰트인지 (설치된 기기에서는 실폰트가
        /// 폴백 계열보다 우선하므로 폴백 계열 검사를 건너뛴다)
        private func isInstalledHancomFont(_ family: String) -> Bool {
            HwpInstalledHancomFonts.index[family] != nil
                || HwpInstalledHancomFonts.index[HwpFontMap.normalize(family)] != nil
        }

        /// 이 시스템의 한글 script 폴백 family — 매핑에 없는 이름을 실제로 해석시켜
        /// 실측한다. 설치 폰트가 플랫폼마다 달라 상수로 굳힐 수 없다.
        private var koreanFallbackFamily: String {
            let font = resolver.resolve(faceName: "ZzUnmappedFaceXYZ", script: .korean, size: 10)
            return CTFontCopyFamilyName(font) as String
        }

        /// 후보 계열 중 하나라도 이 시스템에 등록돼 있으면 그 계열을, 하나도 없으면
        /// script 폴백을 기대값으로 준다. iOS에는 AppleMyungjo·GungSeo 같은 한글
        /// 명조 계열 시스템 폰트가 아예 없어 폴백까지 내려오는 것이 규약상 정답이다
        /// — 계열을 무조건 요구하면 제품이 옳게 동작해도 실패한다.
        private func expectedFamilies(preferring candidates: [String]) -> [String] {
            let registered = Set(CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
            return candidates.contains(where: registered.contains)
                ? candidates
                : [koreanFallbackFamily]
        }

        /// 픽스처 corpus에 실재하지만 매핑이 없어 script 폴백 (한글 = 고딕)까지
        /// 떨어지던 face들. 특히 명조 계열이 고딕으로 렌더되던 것이 회귀 대상이다
        /// (한컴 폰트가 기본 off라 이 폴백이 사용자가 실제로 보는 결과다).
        func testRomanizedAndVariantFacesKeepTheirFamily() {
            let disabled = HwpFontResolver(usesInstalledHancomFonts: false)
            let serifFamilies = expectedFamilies(
                preferring: ["AppleMyungjo", "Nanum Myeongjo", "HCR Batang"]
            )
            for face in ["Myeongjo", "HY Sinmyeongjo"] {
                let family = CTFontCopyFamilyName(
                    disabled.resolve(faceName: face, script: .korean, size: 10)
                ) as String
                expect(serifFamilies).to(
                    contain(family),
                    description: "'\(face)'는 명조 계열인데 \(family)로 해석됐다"
                )
            }
            for face in ["굴림체", "HY헤드라인M", "HY울릉도M", "Apple SD 산돌고딕 Neo"] {
                expect(HwpFontMap.default.candidates(forFaceName: face)).toNot(
                    beEmpty(), description: "'\(face)' 매핑이 비어 script 폴백으로 떨어진다"
                )
            }
        }

        /// 한컴바탕확장은 한글 바탕이 아니라 한자용 송체다 — 문서 자신이
        /// `FaceName.defaultFaceName`에 "FZSong_Superfont"를 적어 둔다.
        func testBatangExtensionMapsToCJKSong() {
            let candidates = HwpFontMap.default.candidates(forFaceName: "한컴바탕확장")
            expect(candidates.first) == "FZSong_Superfont"
            expect(candidates).to(contain("Songti SC"))
            expect(HwpFontMap.default.candidates(forFaceName: "한컴바탕")).toNot(
                contain("Songti SC"),
                description: "확장이 아닌 한컴바탕까지 송체로 보내면 안 된다"
            )
        }

        /// 한컴오피스 번들 폰트는 opt-in — 끈 resolver는 번들에만 있는 face를
        /// 번들 폰트로 해석하지 않고 폴백으로 내려간다. 배포 기본값이 이쪽이라
        /// 라이브러리 소비자가 타 파운드리 라이선스 폰트를 로드하지 않는다.
        func testDisabledResolverDoesNotUseInstalledHancomFonts() throws {
            let bundledOnlyFaces = ["HY헤드라인M", "HY신명조", "함초롬돋움"]
            let available = bundledOnlyFaces.filter {
                HwpInstalledHancomFonts.descriptor(forFaceName: $0) != nil
            }
            try XCTSkipIf(available.isEmpty, "한컴오피스 미설치 — 대조할 번들 폰트가 없다")

            let disabled = HwpFontResolver(usesInstalledHancomFonts: false)
            for face in available {
                let bundled = try XCTUnwrap(HwpInstalledHancomFonts.descriptor(forFaceName: face))
                let bundledFamily = CTFontDescriptorCopyAttribute(
                    bundled, kCTFontFamilyNameAttribute
                ) as? String
                let family = CTFontCopyFamilyName(
                    disabled.resolve(faceName: face, script: .korean, size: 10)
                ) as String
                // 시스템에도 같은 이름의 폰트가 설치돼 있으면 (예: 함초롬체를
                // ~/Library/Fonts 에 정식 설치) 그쪽으로 해석되는 것이 정상이다.
                let registered = Set(CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
                if registered.contains(family) {
                    continue
                }
                expect(family).toNot(
                    equal(bundledFamily),
                    description: "'\(face)'이 opt-in 없이 한컴 번들 폰트로 해석됐다"
                )
            }
        }

        /// 기본값은 환경변수 `HWP_HANCOM_FONTS`를 따른다 (미설정이면 off).
        func testInstalledHancomFontsOptInFollowsEnvironment() {
            let key = HwpInstalledHancomFonts.enableEnvironmentKey
            let original = ProcessInfo.processInfo.environment[key]
            defer {
                if let original {
                    setenv(key, original, 1)
                } else {
                    unsetenv(key)
                }
            }

            unsetenv(key)
            expect(HwpInstalledHancomFonts.isEnabled) == false
            for offValue in ["", "0", "false", " FALSE "] {
                setenv(key, offValue, 1)
                expect(HwpInstalledHancomFonts.isEnabled).to(
                    beFalse(), description: "'\(offValue)'는 off여야 한다"
                )
            }
            for onValue in ["1", "true", "yes"] {
                setenv(key, onValue, 1)
                expect(HwpInstalledHancomFonts.isEnabled).to(
                    beTrue(), description: "'\(onValue)'은 on이어야 한다"
                )
            }
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

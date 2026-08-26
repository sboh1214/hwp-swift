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

        /// face 이름 없는 라벨 (이미지 플레이스홀더)이 쓰는 script 안전망 —
        /// 한국어 안전망은 한글 글리프를 **직접** 가져야 한다 (#125). Helvetica류로
        /// 되돌리면 캐스케이드 의존이 되살아나 이 단언이 잡는다.
        func testKoreanFallbackFontCoversHangulGlyphsDirectly() {
            let font = resolver.fallbackFont(for: .korean, size: 12)

            let characters = Array("이미지".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            let covered = CTFontGetGlyphsForCharacters(
                font, characters, &glyphs, characters.count
            )

            expect(covered) == true
            expect(CTFontGetSize(font)) == 12.0
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

        /// 세리프 라틴 폴백은 resolver의 opt-in 상태를 따라야 한다. 여기서 한컴
        /// 인덱스를 무조건 조회하면 (a) 껐는데도 앱 번들 폰트 파일을 열거하고
        /// (b) 결과가 한컴오피스 설치 여부에 좌우돼 배포 기본 경로의 렌더가
        /// 기기 의존이 된다.
        func testSerifLatinFallbackHonoursOptOut() {
            for face in ["신명 태명조", "한양신명조", "바탕", "HCI Poppy", "휴먼명조"] {
                let rewritten = HwpTextRunBuilder.serifLatinFallback(
                    face, script: .english, usesInstalledHancomFonts: false
                )
                // 한컴 번들에만 있는 이름으로 재작성하면 opt-out이 무의미해진다
                expect(["한컴바탕", "휴먼명조"]).toNot(
                    contain(rewritten),
                    description: "'\(face)'가 opt-out 상태에서 한컴 face '\(rewritten)'로 재작성됐다"
                )
            }
            // 기기와 무관하게 같은 결과 — 한컴 설치 여부가 결과를 바꾸지 않는다
            expect(HwpTextRunBuilder.serifLatinFallback(
                "신명 태명조", script: .english, usesInstalledHancomFonts: false
            )) == "함초롬바탕"
        }

        /// 맵에 없는 face는 문서가 적어 둔 대체 글꼴명으로 구제된다 — 맵은 ~50개인데
        /// 실제 문서의 face는 그보다 훨씬 많아 손으로 다 채울 수 없다.
        func testUnmappedFaceIsRescuedByDocumentAlternative() {
            let resolver = HwpFontResolver(usesInstalledHancomFonts: false)
            let unmapped = "존재하지않는서체XYZ"
            expect(HwpFontMap.default.candidates(forFaceName: unmapped)).to(beEmpty())

            // 대체명 없이는 script 폴백 (한글 = 고딕)
            let bare = CTFontCopyFamilyName(
                resolver.resolve(faceName: unmapped, script: .korean, size: 10)
            ) as String
            // 대체명이 "명조"면 맵을 거쳐 명조 계열로 간다
            let rescued = CTFontCopyFamilyName(
                resolver.resolve(
                    faceName: unmapped, alternatives: ["명조"], script: .korean, size: 10
                )
            ) as String
            let serifFamilies = expectedFamilies(
                preferring: ["AppleMyungjo", "Nanum Myeongjo", "HCR Batang"]
            )
            expect(serifFamilies).to(
                contain(rescued),
                description: "대체 글꼴명이 무시됐다 (bare=\(bare) rescued=\(rescued))"
            )
        }

        /// 큐레이션한 맵이 대체 글꼴명보다 우선한다 — 맵에 있는 face의 검증된
        /// 해석이 문서 데이터로 뒤집히면 안 된다 (기존 렌더 기준선 보존).
        func testCuratedMapWinsOverDocumentAlternative() {
            let resolver = HwpFontResolver(usesInstalledHancomFonts: false)
            let withAlternative = CTFontCopyFamilyName(
                resolver.resolve(
                    faceName: "명조", alternatives: ["굴림"], script: .korean, size: 10
                )
            ) as String
            let withoutAlternative = CTFontCopyFamilyName(
                resolver.resolve(faceName: "명조", script: .korean, size: 10)
            ) as String
            expect(withAlternative) == withoutAlternative
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

    /// 결정론 resolver (`testDeterministic`)가 닫아야 하는 세 축의 가드 —
    /// 시스템 등록 폰트·한컴 번들·문서 대체 글꼴. 하나라도 열리면 같은 문서가
    /// 기여자 머신마다 다르게 조판돼, 커밋된 렌더 골든이 일부 기기에서만 깨진다.
    extension HwpFontResolverTests {
        func testDeterministicResolverReturnsMenlo() {
            let font = HwpFontResolver.testDeterministic.resolve(
                faceName: "unknown-font-xyz", script: .korean, size: 12
            )
            expect(CTFontCopyFamilyName(font) as String) == "Menlo"
        }

        /// 결정론 resolver는 문서 대체 글꼴을 무시해야 한다 — 기본 문서의 `함초롬바탕`은
        /// `defaultFaceName`이 "HCR Batang"이라, 쓰면 그 폰트 설치 여부로 조판이 갈린다.
        /// 대체 후보는 **반드시 설치돼 있는** 이름이어야 한다. 없는 이름으로 바꾸면
        /// 폴백이 어차피 Menlo라 테스트가 공허하게 통과한다.
        func testDeterministicResolverIgnoresDocumentAlternatives() {
            let font = HwpFontResolver.testDeterministic.resolve(
                faceName: "unknown-font-xyz",
                alternatives: ["Helvetica", "HCR Batang"],
                script: .korean,
                size: 12
            )
            expect(CTFontCopyFamilyName(font) as String) == "Menlo"
        }

        /// 결정론 resolver의 마지막 축은 **시스템 설치 폰트**다. 위 두 케이스는 둘 다
        /// `"unknown-font-xyz"`(= 폴백 경로)만 찔러 이 구멍을 통과시켰다 — 실제로
        /// 등록돼 있는 이름을 넣어야 시스템 조회가 닫혔는지 관측된다.
        ///
        /// 이 축이 열려 있으면 HWP 원문 face 이름 (`굴림`·`바탕`·`함초롬바탕`)이
        /// 그 이름으로 등록된 기기에서만 실폰트로 해석돼, 커밋된 골든이 일부
        /// 기여자 머신에서만 깨진다.
        func testDeterministicResolverIgnoresInstalledSystemFonts() {
            let registered = Set(CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
            // 이 기기에 실제로 등록된 이름만 고른다 — 없는 이름은 폴백이 어차피
            // Menlo라 테스트가 공허하게 통과한다. 한글 이름은 있으면 함께 검사한다.
            let candidates = ["Helvetica", "AppleMyungjo", "HCR Batang", "굴림", "함초롬바탕"]
            let installed = candidates.filter(registered.contains)
            expect(installed).toNot(
                beEmpty(), description: "대조할 설치 폰트가 없다 — 후보 목록을 갱신할 것"
            )
            for face in installed {
                let font = HwpFontResolver.testDeterministic.resolve(
                    faceName: face, script: .korean, size: 12
                )
                expect(CTFontCopyFamilyName(font) as String).to(
                    equal("Menlo"),
                    description: "설치된 '\(face)'가 실폰트로 해석됐다 — 결정론 구멍"
                )
            }
        }

        /// 같은 이름을 두 resolver가 **다르게** 봐야 한다. 결정론 쪽만 검사하면
        /// 플래그가 반대로 꽂혀 기본 resolver의 시스템 조회까지 꺼져도 통과한다 —
        /// `resolve`는 모든 문서 로드의 핫패스라 기본 거동이 바뀌면 안 된다.
        func testSystemFontLookupAxisSplitsDefaultAndDeterministicResolvers() {
            let face = "Helvetica"
            let byDefault = CTFontCopyFamilyName(
                resolver.resolve(faceName: face, script: .english, size: 12)
            ) as String
            let deterministic = CTFontCopyFamilyName(
                HwpFontResolver.testDeterministic.resolve(
                    faceName: face, script: .english, size: 12
                )
            ) as String
            expect(byDefault) == face
            expect(deterministic) == "Menlo"
        }

        /// 결정론 resolver는 **대체 폰트까지** 고정한다 (#95).
        ///
        /// 폰트 조회 세 축을 닫아 모든 face를 Menlo로 보내도, Menlo가 못 가진
        /// 글자는 CoreText가 **호스트에 설치된 폰트 목록**에서 고른다. 헌법주석
        /// 코퍼스는 2,054자 중 1,929자가 Menlo 밖이라 사실상 조판 전체가 그 선택에
        /// 달려 있었고, 로마숫자 `Ⅵ`가 이 머신에선 Helvetica-Oblique·CI 러너에선
        /// 다른 폰트로 잡혀 커밋된 좌표 기준선이 갈렸다 (PR #97 CI 실패).
        /// 캐스케이드를 명시하면 선택이 (base, cascade)의 함수가 된다.
        func testDeterministicResolverPinsSubstitutionFont() {
            let font = HwpFontResolver.testDeterministic.resolve(
                faceName: "시스템에없는이름", script: .english, size: 9
            )
            let attributed = NSAttributedString(
                string: "Ⅵ", attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
            let line = CTLineCreateWithAttributedString(attributed)
            let used = (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).compactMap { run -> String? in
                let attributes = CTRunGetAttributes(run) as? [String: Any] ?? [:]
                guard let value = attributes[kCTFontAttributeName as String] else { return nil }
                let runFont = unsafeBitCast(value as CFTypeRef, to: CTFont.self)
                return CTFontCopyPostScriptName(runFont) as String
            }
            expect(used) == ["AppleSDGothicNeo-Regular"]
        }
    }
#endif

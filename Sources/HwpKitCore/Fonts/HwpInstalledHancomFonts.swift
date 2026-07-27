import CoreGraphics
import CoreText
import Foundation

/// 이 기기에 설치된 한컴오피스의 번들 TTF를 찾아 face 이름 → 파일 기반
/// CTFontDescriptor 인덱스를 만든다.
///
/// 한글 문서가 흔히 쓰는 HY헤드라인M/신명 계열/HancomEQN 같은 폰트는 시스템에
/// 없어도 한컴오피스 앱 번들 (`Contents/Resources/Hnc/Shared/TTF/`)에 들어
/// 있다 — 그 폰트로 그리면 한글.app과 같은 글리프/줄바꿈이 된다.
/// 전역 등록 (CTFontManagerRegister…)은 하지 않는다: 파일 descriptor에서
/// 직접 CTFont를 만들 수 있고, 전역 등록은 결정론 테스트 (`testDeterministic`)의
/// 조회 결과까지 바꿔 순서 의존을 만든다.
///
/// **기본 비활성이다** — `isEnabled` 참조.
public enum HwpInstalledHancomFonts {
    /// opt-in 환경변수 이름
    public static let enableEnvironmentKey = "HWP_HANCOM_FONTS"

    /// 한컴오피스 번들 폰트를 조회 대상에 넣을지의 기본값.
    ///
    /// 이 디렉터리에는 한컴이 **자사 오피스 안에서 쓰라고 라이선스받은 타사
    /// 폰트**가 섞여 있다 (2026-07-27 실측: 187개, OS/2 `achVendID` 기준 파운드리
    /// 18종 — Monotype `arial`·`malgun`·`Calibri`, Linotype `pala`, 한양 `HY*`,
    /// 윤디자인 `HAN*` 등). 국내 판례는 서체 도안과 달리 폰트 **파일**을
    /// 컴퓨터프로그램저작물로 보호하므로, 배포되는 라이브러리가 아무 선택 없이
    /// 이들을 로드하지 않도록 기본을 off로 둔다. 한글.app 실물 대조처럼 개발자가
    /// 자기 기기에서 필요할 때만 `HWP_HANCOM_FONTS=1`로 켜며, 켠 뒤 그 폰트들의
    /// 라이선스 준수는 켠 쪽 책임이다.
    ///
    /// nil·빈 값·`0`·`false`는 off, 그 외 값은 on
    /// (`EnvironmentSensitiveTests.isEnabled`와 같은 규칙).
    /// `static let`이 아니라 매번 읽는다 — 테스트가 `setenv` 후 새 resolver를
    /// 만들어 양쪽 분기를 관측할 수 있어야 한다.
    public static var isEnabled: Bool {
        guard let raw = ProcessInfo.processInfo.environment[enableEnvironmentKey] else {
            return false
        }
        let normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return !normalized.isEmpty && normalized != "0" && normalized != "false"
    }

    /// 알려진 한컴오피스 번들 폰트 디렉터리 (버전별 이름 차이는 glob으로 흡수)
    private static let searchRoots = [
        "/Applications/한컴오피스 한글.app/Contents/Resources/Hnc/Shared/TTF",
        "/Applications/Hancom Office HWP.app/Contents/Resources/Hnc/Shared/TTF",
    ]

    /// face 이름 (family/full/PostScript, 원문 + 정규화) → 파일 descriptor.
    /// 한컴오피스가 없으면 빈 인덱스.
    public static let index: [String: CTFontDescriptor] = buildIndex()

    /// 인덱스에서 후보 이름으로 descriptor를 찾는다 (원문 → 정규화 순).
    public static func descriptor(forFaceName faceName: String) -> CTFontDescriptor? {
        if let exact = index[faceName] {
            return exact
        }
        return index[HwpFontMap.normalize(faceName)]
    }

    private static func buildIndex() -> [String: CTFontDescriptor] {
        var result: [String: CTFontDescriptor] = [:]
        var plainKeys = Set<String>()
        let fileManager = FileManager.default
        var fontURLs: [URL] = []
        for root in searchRoots {
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ext == "ttf" || ext == "otf" || ext == "ttc" else { continue }
                fontURLs.append(url)
            }
        }
        // 파일 열거 순서는 API 계약상 무보장 — 동명 충돌 시 승자가 열거 순서에
        // 좌우되지 않도록 경로로 정렬해 인덱스를 디렉터리 내용만의 함수로 만든다
        for url in fontURLs.sorted(by: { $0.path < $1.path }) {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(
                url as CFURL
            ) as? [CTFontDescriptor] else { continue }
            for descriptor in descriptors {
                register(descriptor, into: &result, plainKeys: &plainKeys)
            }
        }
        return result
    }

    /// descriptor의 symbolic traits (Bold/Italic 판별)
    private static func isPlainFace(_ descriptor: CTFontDescriptor) -> Bool {
        guard let traits = CTFontDescriptorCopyAttribute(
            descriptor, kCTFontTraitsAttribute
        ) as? [CFString: Any],
            let symbolic = traits[kCTFontSymbolicTrait] as? UInt32
        else { return true }
        let styled = CTFontSymbolicTraits.traitBold.rawValue
            | CTFontSymbolicTraits.traitItalic.rawValue
        return symbolic & styled == 0
    }

    /// family/스타일 조합 이름과 full name을 인덱스에 넣는다.
    /// 같은 이름 (family/로컬라이즈 이름은 Bold 파일도 동일)에는 보통
    /// (비볼드·비이탤릭) 페이스를 우선한다 — 파일 열거 순서에 따라
    /// HANDotumB.ttf가 먼저 잡혀 '함초롬돋움'이 Bold로 등록되던 문제
    /// (2026-07-10 실물 대조: 전 텍스트가 굵게 렌더).
    private static func register(
        _ descriptor: CTFontDescriptor,
        into result: inout [String: CTFontDescriptor],
        plainKeys: inout Set<String>
    ) {
        var names: [String] = []
        for attribute in [
            kCTFontFamilyNameAttribute,
            kCTFontDisplayNameAttribute,
            kCTFontNameAttribute,
        ] {
            if let name = CTFontDescriptorCopyAttribute(descriptor, attribute) as? String {
                names.append(name)
            }
            // HWP 문서는 한글 이름 ("HY헤드라인M")으로 참조하는데 name table의
            // 기본 이름은 영문 ("HYHeadLine M")일 수 있다 — 로컬라이즈 이름도 수집
            if let localized = CTFontDescriptorCopyLocalizedAttribute(
                descriptor, attribute, nil
            ) as? String {
                names.append(localized)
            }
        }
        let plain = isPlainFace(descriptor)
        for rawName in names {
            for name in [rawName, HwpFontMap.normalize(rawName)] {
                if result[name] == nil {
                    result[name] = descriptor
                    if plain {
                        plainKeys.insert(name)
                    }
                } else if plain, !plainKeys.contains(name) {
                    // 보통 페이스가 스타일 페이스를 대체한다
                    result[name] = descriptor
                    plainKeys.insert(name)
                }
            }
        }
    }
}

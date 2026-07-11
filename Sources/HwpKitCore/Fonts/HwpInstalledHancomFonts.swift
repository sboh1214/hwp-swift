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
public enum HwpInstalledHancomFonts {
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
        for root in searchRoots {
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ext == "ttf" || ext == "otf" || ext == "ttc" else { continue }
                guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(
                    url as CFURL
                ) as? [CTFontDescriptor] else { continue }
                for descriptor in descriptors {
                    register(descriptor, into: &result, plainKeys: &plainKeys)
                }
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

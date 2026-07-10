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
                    register(descriptor, into: &result)
                }
            }
        }
        return result
    }

    /// family/스타일 조합 이름과 full name을 인덱스에 넣는다 (첫 항목 우선 —
    /// 시스템 설치 폰트가 이미 조회에서 앞서므로 여기선 파일 순서면 충분).
    private static func register(
        _ descriptor: CTFontDescriptor,
        into result: inout [String: CTFontDescriptor]
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
        for name in names {
            if result[name] == nil {
                result[name] = descriptor
            }
            let normalized = HwpFontMap.normalize(name)
            if result[normalized] == nil {
                result[normalized] = descriptor
            }
        }
    }
}

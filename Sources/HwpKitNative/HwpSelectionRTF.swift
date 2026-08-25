import CoreGraphics
import CoreText
import Foundation
import HwpKitCore

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

/// 선택 복사의 RTF 직렬화 (#118) — HwpKitCore가 조립한 속성 문자열
/// (`HwpSelectionGeometry.attributedText(for:)`: CT 키 + `hwp.*` 키)을 표준
/// NSAttributedString 키로 정규화한 뒤 RTF `Data`로 만든다.
///
/// HwpKitCore에 둘 수 없는 이유: RTF 직렬화(`data(from:documentAttributes:)`)
/// 와 색·문단 스타일 값 타입(NSColor/UIColor·NSParagraphStyle)이 Foundation이
/// 아니라 AppKit/UIKit 소속이다 (Sources/HwpKitCore/AGENTS.md 첫머리 규약).
enum HwpSelectionRTF {
    static func rtfData(from attributed: NSAttributedString) -> Data? {
        let normalized = normalizedForExport(attributed)
        return try? normalized.data(
            from: NSRange(location: 0, length: normalized.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// CT·`hwp.*` 키 → 표준 키 정규화. 변환 표 (키 이름 동치는 실증 확인):
    /// - 그대로 두는 CT 키 — 이름이 표준 키와 같다: `kCTFont`("NSFont",
    ///   CTFont는 NSFont/UIFont와 toll-free 브리지)·`kCTKern`("NSKern")·
    ///   `kCTStrokeWidth`("NSStrokeWidth").
    /// - 키 개명: "CTForegroundColor"(CGColor) → `.foregroundColor`(플랫폼 색),
    ///   "CTBaselineOffset" → `.baselineOffset`.
    /// - 값 변환: `kCTParagraphStyle`은 키 이름이 "NSParagraphStyle"로 같지만
    ///   값이 `CTParagraphStyle`(toll-free 아님)이라 `NSParagraphStyle`로
    ///   다시 만든다 — 안 바꾸면 RTF 작성기가 CF 타입에 ObjC 메시지를 보낸다.
    /// - `hwp.*` 명시 변환: `underlineStyle`/`underlineColor`·
    ///   `strikethroughStyle`/`strikethroughColor`(둘 다 값 1 = 단선)는 표준
    ///   밑줄·취소선으로, `hyperlink`(String)는 `.link`(URL)로 승격하되 URL
    ///   변환 실패 시 링크 속성만 버린다.
    /// - 나머지 `hwp.*`(그림자·양각·음영·강조점 등 렌더러 전용)와
    ///   from-context 플래그는 제거한다 — 전경색은 모든 run에 이미
    ///   "CTForegroundColor"로 실려 있어 잃는 정보가 없다. 제거는 개별 열거가
    ///   아니라 "hwp." 접두사 일괄이라 미래 키도 새지 않는다.
    static func normalizedForExport(_ attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let text = attributed.string as NSString
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length)
        ) { attributes, range, _ in
            result.append(NSAttributedString(
                string: text.substring(with: range),
                attributes: normalizedAttributes(attributes)
            ))
        }
        return result
    }

    private static let ctForegroundColorKey =
        NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    private static let ctBaselineOffsetKey =
        NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)
    private static let ctForegroundFromContextKey =
        NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)

    static func normalizedAttributes(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var normalized = attributes
        // hwp.* 명시 변환 — 접두사 일괄 제거 전에 값을 표준 키로 옮긴다
        if attributes[HwpAttributedStringKey.underlineStyle] != nil {
            normalized[.underlineStyle] = NSNumber(value: NSUnderlineStyle.single.rawValue)
            if let color = cgColor(attributes[HwpAttributedStringKey.underlineColor]) {
                normalized[.underlineColor] = platformColor(from: color)
            }
        }
        if attributes[HwpAttributedStringKey.strikethroughStyle] != nil {
            normalized[.strikethroughStyle] =
                NSNumber(value: NSUnderlineStyle.single.rawValue)
            if let color = cgColor(attributes[HwpAttributedStringKey.strikethroughColor]) {
                normalized[.strikethroughColor] = platformColor(from: color)
            }
        }
        if let link = attributes[HwpAttributedStringKey.hyperlink] as? String,
           let url = URL(string: link)
        {
            normalized[.link] = url
        }
        // 키 개명 2종
        if let color = cgColor(normalized.removeValue(forKey: ctForegroundColorKey)) {
            normalized[.foregroundColor] = platformColor(from: color)
        }
        if let offset = normalized.removeValue(forKey: ctBaselineOffsetKey) as? NSNumber {
            normalized[.baselineOffset] = offset
        }
        // 값 변환: CTParagraphStyle → NSParagraphStyle (키 이름은 같다)
        if let style = normalized[.paragraphStyle],
           CFGetTypeID(style as CFTypeRef) == CTParagraphStyleGetTypeID()
        {
            normalized[.paragraphStyle] = nsParagraphStyle(
                from: style as! CTParagraphStyle // swiftlint:disable:this force_cast
            )
        }
        // 렌더러 전용 잔여 제거
        normalized[ctForegroundFromContextKey] = nil
        for key in normalized.keys where key.rawValue.hasPrefix("hwp.") {
            normalized[key] = nil
        }
        return normalized
    }

    private static func cgColor(_ value: Any?) -> CGColor? {
        guard let value, CFGetTypeID(value as CFTypeRef) == CGColor.typeID
        else { return nil }
        return (value as! CGColor) // swiftlint:disable:this force_cast
    }

    private static func platformColor(from cgColor: CGColor) -> PlatformColor {
        #if os(macOS)
            PlatformColor.hwpColor(from: cgColor)
        #else
            PlatformColor(hwpCgColor: cgColor)
        #endif
    }

    // MARK: - 문단 스타일 값 변환

    /// `HwpParagraphLayout.ctParagraphStyle`이 싣는 지정자만 옮긴다 —
    /// 정렬·들여쓰기 3종·문단 간격 2종·행간 3종·탭 정지.
    /// (CT `maximumLineSpacing`은 NSParagraphStyle에 대응이 없어 버린다.)
    private static func nsParagraphStyle(from ct: CTParagraphStyle) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        var alignment = CTTextAlignment.natural
        if CTParagraphStyleGetValueForSpecifier(
            ct, .alignment, MemoryLayout<CTTextAlignment>.size, &alignment
        ) {
            style.alignment = nsTextAlignment(from: alignment)
        }
        copyFloat(ct, .firstLineHeadIndent) { style.firstLineHeadIndent = $0 }
        copyFloat(ct, .headIndent) { style.headIndent = $0 }
        copyFloat(ct, .tailIndent) { style.tailIndent = $0 }
        copyFloat(ct, .paragraphSpacingBefore) { style.paragraphSpacingBefore = $0 }
        copyFloat(ct, .paragraphSpacing) { style.paragraphSpacing = $0 }
        copyFloat(ct, .lineSpacingAdjustment) { style.lineSpacing = $0 }
        copyFloat(ct, .minimumLineHeight) { style.minimumLineHeight = $0 }
        copyFloat(ct, .maximumLineHeight) { style.maximumLineHeight = $0 }
        // 탭 정지: CFArray를 +0 참조로 받는다 (버퍼에 담기는 것은 포인터)
        var tabsPointer: UnsafeMutableRawPointer?
        if CTParagraphStyleGetValueForSpecifier(
            ct, .tabStops, MemoryLayout<UnsafeMutableRawPointer?>.size, &tabsPointer
        ), let tabsPointer {
            let tabs = Unmanaged<CFArray>.fromOpaque(tabsPointer).takeUnretainedValue()
            style.tabStops = ((tabs as? [CTTextTab]) ?? []).map { tab in
                NSTextTab(
                    textAlignment: nsTextAlignment(from: CTTextTabGetAlignment(tab)),
                    location: CTTextTabGetLocation(tab)
                )
            }
        }
        return style
    }

    private static func copyFloat(
        _ ct: CTParagraphStyle,
        _ specifier: CTParagraphStyleSpecifier,
        into assign: (CGFloat) -> Void
    ) {
        var value: CGFloat = 0
        if CTParagraphStyleGetValueForSpecifier(
            ct, specifier, MemoryLayout<CGFloat>.size, &value
        ) {
            assign(value)
        }
    }

    private static func nsTextAlignment(from alignment: CTTextAlignment) -> NSTextAlignment {
        switch alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        case .natural: .natural
        @unknown default: .natural
        }
    }
}

import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

/// RTF 직렬화 (#118) — CT·`hwp.*` 키 → 표준 키 정규화 표와 재파싱 왕복.
final class HwpSelectionRTFTests: XCTestCase {
    private let boldFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 14, nil)
    private let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)

    private func components(_ color: Any?) -> [CGFloat]? {
        (color as? PlatformColor)?.cgColor.components
    }

    // MARK: - 정규화 표

    func testForegroundColorKeyIsRenamedWithPlatformValue() {
        let normalized = HwpSelectionRTF.normalizedAttributes([
            NSAttributedString.Key(
                kCTForegroundColorAttributeName as String
            ): red,
        ])

        expect(normalized[NSAttributedString.Key(
            kCTForegroundColorAttributeName as String
        )]).to(beNil())
        expect(self.components(normalized[.foregroundColor])?.first)
            .to(beCloseTo(1.0))
    }

    func testBaselineOffsetKeyIsRenamed() {
        let normalized = HwpSelectionRTF.normalizedAttributes([
            NSAttributedString.Key(
                kCTBaselineOffsetAttributeName as String
            ): NSNumber(value: 3.5),
        ])

        expect(normalized[.baselineOffset] as? NSNumber) == NSNumber(value: 3.5)
        expect(normalized[NSAttributedString.Key(
            kCTBaselineOffsetAttributeName as String
        )]).to(beNil())
    }

    func testUnderlineAndStrikethroughConvertWithColors() {
        let normalized = HwpSelectionRTF.normalizedAttributes([
            HwpAttributedStringKey.underlineStyle: NSNumber(value: 1),
            HwpAttributedStringKey.underlineColor: blue,
            HwpAttributedStringKey.strikethroughStyle: NSNumber(value: 1),
            HwpAttributedStringKey.strikethroughColor: red,
        ])

        expect(normalized[.underlineStyle] as? NSNumber)
            == NSNumber(value: NSUnderlineStyle.single.rawValue)
        expect(self.components(normalized[.underlineColor])) == [0, 0, 1, 1]
        expect(normalized[.strikethroughStyle] as? NSNumber)
            == NSNumber(value: NSUnderlineStyle.single.rawValue)
        expect(self.components(normalized[.strikethroughColor])) == [1, 0, 0, 1]
        expect(normalized[HwpAttributedStringKey.underlineStyle]).to(beNil())
        expect(normalized[HwpAttributedStringKey.underlineColor]).to(beNil())
    }

    func testHyperlinkPromotesToLinkAndInvalidURLDropsOnlyTheLink() {
        let promoted = HwpSelectionRTF.normalizedAttributes([
            HwpAttributedStringKey.hyperlink: "https://example.com/a",
        ])
        expect(promoted[.link] as? URL) == URL(string: "https://example.com/a")
        expect(promoted[HwpAttributedStringKey.hyperlink]).to(beNil())

        // URL 변환이 실패하면 (#118 미결 결정의 폴백) 링크 속성만 버린다.
        // macOS 14+/iOS 17+의 URL(string:)은 RFC 3986 관대 파서라 공백도
        // 퍼센트 인코딩해 성공한다 — 남은 실패 사례는 빈 문자열이다.
        let dropped = HwpSelectionRTF.normalizedAttributes([
            HwpAttributedStringKey.hyperlink: "",
        ])
        expect(dropped[.link]).to(beNil())
        expect(dropped[HwpAttributedStringKey.hyperlink]).to(beNil())
    }

    func testRendererOnlyKeysAreStrippedByPrefix() {
        // 미래에 추가될 hwp.* 키도 접두사 일괄 제거로 새지 않아야 한다
        let normalized = HwpSelectionRTF.normalizedAttributes([
            HwpAttributedStringKey.shadowColor: red,
            HwpAttributedStringKey.reliefFaceColor: red,
            HwpAttributedStringKey.shadeColor: blue,
            NSAttributedString.Key("hwp.futureKey"): NSNumber(value: 1),
            NSAttributedString.Key(
                kCTForegroundColorFromContextAttributeName as String
            ): NSNumber(value: true),
        ])

        expect(normalized.keys.filter { $0.rawValue.hasPrefix("hwp.") }).to(beEmpty())
        expect(normalized[NSAttributedString.Key(
            kCTForegroundColorFromContextAttributeName as String
        )]).to(beNil())
    }

    func testParagraphStyleValueConvertsToNSParagraphStyle() throws {
        var alignment = CTTextAlignment.center
        var indent = CGFloat(12)
        var tabsArray = [CTTextTabCreate(.left, 100, nil)] as CFArray
        let ctStyle = withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &indent) { indentPointer in
                withUnsafePointer(to: &tabsArray) { tabsPointer in
                    let settings = [
                        CTParagraphStyleSetting(
                            spec: .alignment,
                            valueSize: MemoryLayout<CTTextAlignment>.size,
                            value: alignmentPointer
                        ),
                        CTParagraphStyleSetting(
                            spec: .firstLineHeadIndent,
                            valueSize: MemoryLayout<CGFloat>.size,
                            value: indentPointer
                        ),
                        CTParagraphStyleSetting(
                            spec: .tabStops,
                            valueSize: MemoryLayout<CFArray>.size,
                            value: tabsPointer
                        ),
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }

        let normalized = HwpSelectionRTF.normalizedAttributes([
            .paragraphStyle: ctStyle,
        ])

        let style = try XCTUnwrap(normalized[.paragraphStyle] as? NSParagraphStyle)
        expect(style.alignment) == .center
        expect(style.firstLineHeadIndent) == 12
        expect(style.tabStops.first?.location) == 100
    }

    // MARK: - RTF 재파싱 왕복

    func testRTFRoundTripPreservesFontColorUnderlineAndLink() throws {
        let source = NSMutableAttributedString()
        source.append(NSAttributedString(string: "링크", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: boldFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): red,
            HwpAttributedStringKey.hyperlink: "https://example.com",
        ]))
        source.append(NSAttributedString(string: "밑줄", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: boldFont,
            HwpAttributedStringKey.underlineStyle: NSNumber(value: 1),
            HwpAttributedStringKey.underlineColor: blue,
            // 그림자 장식 run — from-context여도 전경색이 살아야 한다 (#118)
            HwpAttributedStringKey.shadowColor: blue,
            NSAttributedString.Key(
                kCTForegroundColorFromContextAttributeName as String
            ): NSNumber(value: true),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): red,
        ]))

        let data = try XCTUnwrap(HwpSelectionRTF.rtfData(from: source))
        let parsed = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )

        expect(parsed.string) == "링크밑줄"
        let font = parsed.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        expect(font?.fontName) == "Helvetica-Bold"
        expect(parsed.attribute(.link, at: 0, effectiveRange: nil)).toNot(beNil())
        expect(
            parsed.attribute(.underlineStyle, at: 2, effectiveRange: nil) as? NSNumber
        ) == NSNumber(value: NSUnderlineStyle.single.rawValue)
        // 장식 run의 전경색 — hwp.shadowColor(청)가 아니라 faceColor(적)다
        let foreground = components(
            parsed.attribute(.foregroundColor, at: 2, effectiveRange: nil)
        )
        expect(foreground?.first).to(beCloseTo(1.0, within: 0.02))
        expect(parsed.string.contains("\u{FFFC}")) == false
    }
}

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

    func testBaselineComesFromGlyphOffsetAndRawCTKeyIsDropped() {
        // 기준선 공급원은 hwp.glyphBaselineOffset(양수 = 위, NS 규약 일치)
        // 하나다. HWP 원시 부호(양수 = 아래)의 "CTBaselineOffset"을 그대로
        // 옮기면 복사한 글자가 앱 렌더와 반대 방향으로 붙는다.
        let normalized = HwpSelectionRTF.normalizedAttributes([
            NSAttributedString.Key(
                kCTBaselineOffsetAttributeName as String
            ): NSNumber(value: 3.5),
            HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: -3.5),
        ])

        expect(normalized[.baselineOffset] as? NSNumber) == NSNumber(value: -3.5)
        expect(normalized[NSAttributedString.Key(
            kCTBaselineOffsetAttributeName as String
        )]).to(beNil())

        // 글자위치 0이면 glyph 키가 없고, 오프셋 없음이 올바른 결과다
        let zero = HwpSelectionRTF.normalizedAttributes([
            NSAttributedString.Key(
                kCTBaselineOffsetAttributeName as String
            ): NSNumber(value: 0),
        ])
        expect(zero[.baselineOffset]).to(beNil())
    }

    func testSuperscriptBaselineShiftSurvives() {
        // 첨자는 축소 폰트 + hwp.glyphBaselineOffset(합산)만 싣는다 —
        // 접두사 일괄 제거보다 먼저 .baselineOffset으로 옮겨야
        // x²가 본문 기준선의 작은 2로 붙지 않는다.
        let normalized = HwpSelectionRTF.normalizedAttributes([
            HwpAttributedStringKey.glyphBaselineOffset: NSNumber(value: 4.2),
        ])

        expect(normalized[.baselineOffset] as? NSNumber) == NSNumber(value: 4.2)
        expect(normalized.keys.filter { $0.rawValue.hasPrefix("hwp.") }).to(beEmpty())
    }

    func testStandardNamedCTKeysPassThroughUnchanged() {
        // kCTKern("NSKern")·kCTStrokeWidth("NSStrokeWidth")는 키 이름이
        // 표준과 같아 무변환 통과가 계약이다.
        let normalized = HwpSelectionRTF.normalizedAttributes([
            NSAttributedString.Key(kCTKernAttributeName as String):
                NSNumber(value: 1.2),
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String):
                NSNumber(value: 4.0),
        ])

        expect(normalized[.kern] as? NSNumber) == NSNumber(value: 1.2)
        expect(normalized[.strokeWidth] as? NSNumber) == NSNumber(value: 4.0)
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

    /// 가운데 정렬 + 들여쓰기·간격·행간·탭을 실은 CTParagraphStyle —
    /// `HwpParagraphLayout.StyleValuePointers`와 같은 할당 패턴.
    private func makeCTStyle() -> CTParagraphStyle {
        func pointer<T>(_ value: T) -> UnsafeMutablePointer<T> {
            let allocated = UnsafeMutablePointer<T>.allocate(capacity: 1)
            allocated.initialize(to: value)
            return allocated
        }
        let alignment = pointer(CTTextAlignment.center)
        let firstLineHeadIndent = pointer(CGFloat(12))
        let headIndent = pointer(CGFloat(6))
        let paragraphSpacing = pointer(CGFloat(4))
        let minimumLineHeight = pointer(CGFloat(20))
        let tabs = pointer([CTTextTabCreate(.left, 100, nil)] as CFArray)
        defer {
            alignment.deallocate()
            firstLineHeadIndent.deallocate()
            headIndent.deallocate()
            paragraphSpacing.deallocate()
            minimumLineHeight.deallocate()
            tabs.deinitialize(count: 1)
            tabs.deallocate()
        }
        let settings = [
            CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size, value: alignment
            ),
            CTParagraphStyleSetting(
                spec: .firstLineHeadIndent,
                valueSize: MemoryLayout<CGFloat>.size, value: firstLineHeadIndent
            ),
            CTParagraphStyleSetting(
                spec: .headIndent,
                valueSize: MemoryLayout<CGFloat>.size, value: headIndent
            ),
            CTParagraphStyleSetting(
                spec: .paragraphSpacing,
                valueSize: MemoryLayout<CGFloat>.size, value: paragraphSpacing
            ),
            CTParagraphStyleSetting(
                spec: .minimumLineHeight,
                valueSize: MemoryLayout<CGFloat>.size, value: minimumLineHeight
            ),
            CTParagraphStyleSetting(
                spec: .tabStops,
                valueSize: MemoryLayout<CFArray>.size, value: tabs
            ),
        ]
        return CTParagraphStyleCreate(settings, settings.count)
    }

    func testParagraphStyleValueConvertsToNSParagraphStyle() throws {
        let normalized = HwpSelectionRTF.normalizedAttributes([
            .paragraphStyle: makeCTStyle(),
        ])

        let style = try XCTUnwrap(normalized[.paragraphStyle] as? NSParagraphStyle)
        expect(style.alignment) == .center
        expect(style.firstLineHeadIndent) == 12
        expect(style.headIndent) == 6
        expect(style.paragraphSpacing) == 4
        expect(style.minimumLineHeight) == 20
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
            HwpAttributedStringKey.strikethroughStyle: NSNumber(value: 1),
            HwpAttributedStringKey.strikethroughColor: red,
            // 그림자 장식 run — from-context여도 전경색이 살아야 한다 (#118)
            HwpAttributedStringKey.shadowColor: blue,
            NSAttributedString.Key(
                kCTForegroundColorFromContextAttributeName as String
            ): NSNumber(value: true),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): red,
        ]))
        source.addAttribute(
            .paragraphStyle, value: makeCTStyle(),
            range: NSRange(location: 0, length: source.length)
        )

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
        expect(
            parsed.attribute(.strikethroughStyle, at: 2, effectiveRange: nil)
                as? NSNumber
        ) == NSNumber(value: NSUnderlineStyle.single.rawValue)
        // 장식 run의 전경색 — hwp.shadowColor(청)가 아니라 faceColor(적)다
        let foreground = components(
            parsed.attribute(.foregroundColor, at: 2, effectiveRange: nil)
        )
        expect(foreground?.first).to(beCloseTo(1.0, within: 0.02))
        // 문단 스타일이 RTF를 건너 살아남는다 (정렬·첫 줄 들여쓰기)
        let paragraph = try XCTUnwrap(
            parsed.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        )
        expect(paragraph.alignment) == .center
        expect(paragraph.firstLineHeadIndent).to(beCloseTo(12, within: 0.1))
        // U+FFFC 미유입은 Core 층 계약(strippingControlMarkerRuns)이라
        // HwpSelectionGeometryAttributedTests가 실제 마커 입력으로 잠근다.
    }
}

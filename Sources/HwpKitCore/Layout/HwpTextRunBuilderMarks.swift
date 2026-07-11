import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 변경 추적 (PARA_RANGE_TAG kind 16/17)과 메모 (댓글) 앵커 범위 마킹.
extension HwpTextRunBuilder {
    /// PARA_RANGE_TAG의 변경 추적 마크 (16 삽입 / 17 삭제)를 한글.app처럼
    /// 표시한다: 삽입 = 빨강 글자 + 빨강 밑줄, 삭제 = 빨강 글자 + 빨강 취소선.
    func applyTrackChangeMark(
        _ mark: UInt32,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        guard mark == 16 || mark == 17 else { return }
        let red = CGColor(srgbRed: 0.87, green: 0.14, blue: 0.1, alpha: 1)
        attributes[kCTForegroundColorAttributeName as NSAttributedString.Key] = red
        if mark == 17 {
            attributes[HwpAttributedStringKey.strikethroughStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.strikethroughColor] = red
        } else {
            attributes[.underlineStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = red
            attributes[kCTUnderlineColorAttributeName as NSAttributedString.Key] = red
        }
    }

    /// position (원본 WCHAR 스트림 위치)이 속한 변경 추적 range tag의 kind.
    /// 16 (삽입)/17 (삭제) 외의 태그는 무시한다.
    static func trackChangeMark(
        at position: UInt32,
        in paragraph: CoreHwp.HwpParagraph
    ) -> UInt32 {
        for tag in paragraph.paraRangeTagArray ?? [] {
            let kind = tag.tag >> 24
            guard kind == 16 || kind == 17 else { continue }
            if position >= tag.start, position < tag.end {
                return kind
            }
        }
        return 0
    }

    /// 메모 (댓글) 필드가 감싸는 앵커 텍스트의 WCHAR 스트림 범위.
    /// extended 컨트롤 문자 (필드 시작, ctrl 순서 = ctrlHeaderArray 순서)부터
    /// 다음 필드 끝 inline 문자 (코드 4)까지.
    static func memoAnchorRanges(
        in paragraph: CoreHwp.HwpParagraph
    ) -> [Range<UInt32>] {
        guard let ctrls = paragraph.ctrlHeaderArray,
              ctrls.contains(where: {
                  if case .memo = $0 {
                      true
                  } else {
                      false
                  }
              })
        else { return [] }
        var ranges: [Range<UInt32>] = []
        var position: UInt32 = 0
        var ordinal = 0
        var activeStart: UInt32?
        for hwpChar in paragraph.paraText?.charArray ?? [] {
            let length: UInt32 = hwpChar.type == .char ? 1 : 8
            if hwpChar.type == .extended {
                if ordinal < ctrls.count, case .memo = ctrls[ordinal] {
                    activeStart = position + length
                }
                ordinal += 1
            } else if hwpChar.type == .inline, hwpChar.value == 4,
                      let start = activeStart
            {
                if position > start {
                    ranges.append(start ..< position)
                }
                activeStart = nil
            }
            position += length
        }
        return ranges
    }
}

extension HwpTextRunBuilder {
    /// 한글의 기본 공백 폭 규칙: '글꼴에 어울리는 빈칸'(doesAdjustBlank)이
    /// 꺼져 있으면 공백 advance를 폰트 고유 폭 대신 글자 크기의 1/2로 맞춘다.
    /// 실측 (2026-07-10 plain-text-minimal 실물 픽셀): 한글.app 공백 advance
    /// ≈ 0.5em, HCR Batang 고유 공백 ≈ 0.3em — 부족분을 kern으로 더한다.
    static func applyFixedSpaceWidth(to attributed: NSMutableAttributedString) {
        let text = attributed.string as NSString
        var index = 0
        while index < text.length {
            if text.character(at: index) == 0x20 {
                let attrs = attributed.attributes(at: index, effectiveRange: nil)
                if let fontValue = attrs[kCTFontAttributeName as NSAttributedString.Key],
                   CFGetTypeID(fontValue as CFTypeRef) == CTFontGetTypeID()
                {
                    // swiftlint:disable:next force_cast
                    let font = fontValue as! CTFont
                    let kern = Self.fixedSpaceKern(for: font)
                    if abs(kern) > 0.01 {
                        attributed.addAttribute(
                            kCTKernAttributeName as NSAttributedString.Key,
                            value: NSNumber(value: Double(kern)),
                            range: NSRange(location: index, length: 1)
                        )
                    }
                }
            }
            index += 1
        }
    }

    /// 공백 글리프의 고유 advance와 0.5em 목표의 차 (폰트별 캐시 없이 즉석 계산 —
    /// CTFontGetAdvancesForGlyphs는 가볍고 chunk 단위로만 불린다)
    static func fixedSpaceKern(for font: CTFont) -> CGFloat {
        var character: UniChar = 0x20
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return 0 }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        let target = CTFontGetSize(font) * 0.5
        return target - advance.width
    }
}

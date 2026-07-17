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
            // CT 밑줄은 폰트 밑줄 위치 (얕음) — 한글 실물은 베이스라인에서
            // 반 x-height가량 아래 (track-changes 실측). 렌더러가 직접 그린다.
            attributes[HwpAttributedStringKey.trackInsertUnderline] = red
        }
    }

    /// 변경 추적 range tag (kind 16 삽입 / 17 삭제)를 시작 위치 오름차순으로
    /// 정렬해 돌려준다. 문자 루프에서 단조 커서로 sweep하기 위한 것으로,
    /// 문자마다 전체 배열을 다시 스캔하는 O(문자×태그)를 없앤다 (#11).
    static func trackChangeIntervals(
        in paragraph: CoreHwp.HwpParagraph
    ) -> [(start: UInt32, end: UInt32, kind: UInt32)] {
        (paragraph.paraRangeTagArray ?? []).compactMap { tag in
            let kind = tag.tag >> 24
            guard kind == 16 || kind == 17 else { return nil }
            return (start: tag.start, end: tag.end, kind: kind)
        }
        .sorted { $0.start < $1.start }
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
        // 필드는 코드 3 시작 ~ 코드 4 끝으로 LIFO 중첩된다 — 필드 depth와
        // depth별 memo 스택으로 매칭 종결자에서만 닫아, memo 안 중첩 필드
        // (하이퍼링크 등)의 끝 마커가 바깥 앵커를 조기 종료하거나 중첩 memo가
        // 바깥 start를 덮지 않게 한다 (HwpTextRunBuilder 하이퍼링크 스택과 동일, #2).
        var ranges: [Range<UInt32>] = []
        var position: UInt32 = 0
        var ordinal = 0
        var fieldDepth = 0
        var memoStack: [(depth: Int, start: UInt32)] = []
        for hwpChar in paragraph.paraText?.charArray ?? [] {
            let length: UInt32 = hwpChar.type == .char ? 1 : 8
            if hwpChar.type == .extended {
                if hwpChar.value == 3 {
                    fieldDepth += 1
                    if ordinal < ctrls.count, case .memo = ctrls[ordinal] {
                        memoStack.append((depth: fieldDepth, start: position + length))
                    }
                }
                ordinal += 1
            } else if hwpChar.type == .inline, hwpChar.value == 4 {
                if let top = memoStack.last, top.depth == fieldDepth {
                    if position > top.start {
                        ranges.append(top.start ..< position)
                    }
                    memoStack.removeLast()
                }
                if fieldDepth > 0 {
                    fieldDepth -= 1
                }
            }
            position += length
        }
        // 빌더의 단조 sweep은 lowerBound 오름차순을 전제한다 — 중첩 close 순서
        // (안쪽 먼저)로 어긋난 정렬을 복원한다.
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
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
                    // 공백 폭 목표는 첨자 축소 전·상대크기 적용 후 크기의
                    // 0.5em (라운드 11·12 실측: 첨자 행 공백 = 본문 공백,
                    // 상대크기 170 줄 공백 = 1.7배)
                    let base = (attrs[HwpAttributedStringKey.spaceTargetSize]
                        as? NSNumber).map { CGFloat($0.doubleValue) }
                    let kern = Self.fixedSpaceKern(for: font, targetEm: base)
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
    static func fixedSpaceKern(for font: CTFont, targetEm: CGFloat? = nil) -> CGFloat {
        var character: UniChar = 0x20
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return 0 }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        let target = (targetEm ?? CTFontGetSize(font)) * 0.5
        return target - advance.width
    }
}

extension HwpTextRunBuilder {
    /// 위 첨자 글꼴 크기 배율 — 실물 실측 (CharShapeProperty): 본문의 ~67%
    static let superscriptScale: CGFloat = 0.67
    /// 위 첨자 베이스라인 상승 배율 (기준 글자 크기 대비)
    static let superscriptBaselineRatio: CGFloat = 0.33
    /// 아래 첨자 베이스라인 하강 배율 (실물: 다음 줄 방향 ~0.35줄)
    static let subscriptBaselineRatio: CGFloat = 0.30
}

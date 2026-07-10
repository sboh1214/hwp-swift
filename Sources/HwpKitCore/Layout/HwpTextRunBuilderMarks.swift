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
            attributes[.strikethroughStyle] = NSNumber(value: 1)
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

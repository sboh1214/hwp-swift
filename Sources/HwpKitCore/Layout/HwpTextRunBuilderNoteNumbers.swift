import CoreGraphics
import CoreHwp
import CoreText
import Foundation

// 각주/미주 자동 번호 텍스트 (표 133/142) — HwpTextRunBuilder의 마커 치환 입력

public extension HwpTextRunBuilder {
    /// 앞/뒤 장식 문자 (WCHAR, 0이면 없음)를 붙인 번호 문자열 (표 133/142)
    static func decoratedNoteNumber(
        number: Int,
        shape: Int,
        decorationHead: CoreHwp.WCHAR,
        decorationTail: CoreHwp.WCHAR
    ) -> String {
        var text = HwpNumberFormat.string(for: number, shape: shape)
        if decorationHead != 0, let scalar = Unicode.Scalar(decorationHead) {
            text = String(Character(scalar)) + text
        }
        if decorationTail != 0, let scalar = Unicode.Scalar(decorationTail) {
            text += String(Character(scalar))
        }
        return text
    }

    /// 구역 각주/미주 모양 (표 133: 번호 모양 bits 0-7 + 장식 문자) 기준의 번호 문자열
    static func noteNumberText(
        number: Int,
        footnoteShape: CoreHwp.HwpFootnoteShape?
    ) -> String {
        decoratedNoteNumber(
            number: number,
            shape: footnoteShape.map { Int($0.property & 0xFF) } ?? 0,
            decorationHead: footnoteShape?.decorationHeadRawValue ?? 0,
            decorationTail: footnoteShape?.decorationTailRawValue ?? 0
        )
    }

    /// 각주/미주 문단 첫머리의 자동 번호 (ext18 atno) 마커 치환 목록.
    ///
    /// 장식 문자/번호 모양은 atno 자신의 payload (표 142)를 우선하고,
    /// 비어 있으면 구역 각주/미주 모양 (표 133)으로 폴백한다.
    /// 위 첨자 여부는 표 143 bit 12.
    static func autoNumberReplacements(
        in paragraph: CoreHwp.HwpParagraph,
        number: Int,
        footnoteShape: CoreHwp.HwpFootnoteShape?
    ) -> [Int: HwpControlMarkerReplacement] {
        guard let ctrls = paragraph.ctrlHeaderArray else { return [:] }
        var replacements: [Int: HwpControlMarkerReplacement] = [:]
        for (ctrlIndex, ctrl) in ctrls.enumerated() {
            guard case let .autoNumber(other) = ctrl else { continue }
            if let info = other.autoNumberInfo {
                guard info.kind == .footnote || info.kind == .endnote else { continue }
                let hasOwnDecoration = info.decorationHead != 0 || info.decorationTail != 0
                    || info.numberShapeRawValue != 0
                let text = hasOwnDecoration
                    ? decoratedNoteNumber(
                        number: number,
                        shape: info.numberShapeRawValue,
                        decorationHead: info.decorationHead,
                        decorationTail: info.decorationTail
                    )
                    : noteNumberText(number: number, footnoteShape: footnoteShape)
                replacements[ctrlIndex] = HwpControlMarkerReplacement(
                    text: text,
                    isSuperscript: info.isSuperscript
                )
            } else {
                replacements[ctrlIndex] = HwpControlMarkerReplacement(
                    text: noteNumberText(number: number, footnoteShape: footnoteShape)
                )
            }
        }
        return replacements
    }

    /// 이미 구워진 각주/미주 참조 마커 텍스트를 새 번호로 다시 쓴다 (#95).
    ///
    /// 조각이 실릴 페이지가 정해진 뒤에야 알 수 있는 번호가 있다 — "쪽마다 새로
    /// 시작"(표 134) 구역에서 페이지에 걸친 문단이 그렇다. 아직 치환되지 않은
    /// U+FFFC 마커는 건드리지 않는다: 번호가 없던 자리에 번호를 새로 만들면
    /// 참조가 없던 곳에 참조가 생긴다.
    static func renumberingNoteMarkers(
        in slice: NSAttributedString,
        replacements: [Int: HwpControlMarkerReplacement]
    ) -> NSAttributedString {
        guard !replacements.isEmpty, slice.length > 0 else { return slice }
        var edits: [(range: NSRange, text: String)] = []
        slice.enumerateAttribute(
            HwpAttributedStringKey.controlIndex,
            in: NSRange(location: 0, length: slice.length)
        ) { value, range, _ in
            guard let ordinal = (value as? NSNumber)?.intValue,
                  let replacement = replacements[ordinal], !replacement.text.isEmpty
            else { return }
            let current = slice.attributedSubstring(from: range).string
            guard current != replacement.text, current != "\u{FFFC}" else { return }
            edits.append((range, replacement.text))
        }
        guard !edits.isEmpty else { return slice }
        let output = NSMutableAttributedString(attributedString: slice)
        // 뒤에서부터 바꿔야 앞 편집의 길이 변화가 뒤 range를 어긋내지 않는다.
        for edit in edits.reversed() {
            output.replaceCharacters(
                in: edit.range,
                with: NSAttributedString(
                    string: edit.text,
                    attributes: slice.attributes(at: edit.range.location, effectiveRange: nil)
                )
            )
        }
        return output
    }
}

/// 첨자 속성 (표 33 위/아래 첨자와 각주 참조 번호가 공유)
extension HwpTextRunBuilder {
    /// 위 첨자 (각주 참조 번호): 글꼴 크기를 줄이고 베이스라인을 올린다.
    func applySuperscript(
        to attributes: inout [NSAttributedString.Key: Any],
        shape: CoreHwp.HwpCharShape
    ) {
        let baseSize = HwpUnits.points(fromHwpUnit: shape.baseSize)
        let fontKey = kCTFontAttributeName as NSAttributedString.Key
        if let value = attributes[fontKey], CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() {
            let font = value as! CTFont // swiftlint:disable:this force_cast
            attributes[fontKey] = CTFontCreateCopyWithAttributes(
                font,
                CTFontGetSize(font) * Self.superscriptScale,
                nil,
                nil
            )
        }
        // CTFramesetter는 kCTBaselineOffset을 무시한다 — 렌더가 반영하는
        // 커스텀 키 (drawRun 글리프 세로 이동)로 싣는다
        let baselineKey = HwpAttributedStringKey.glyphBaselineOffset
        let existing = (attributes[baselineKey] as? NSNumber)?.doubleValue ?? 0
        attributes[baselineKey] = NSNumber(
            value: existing + Double(baseSize * Self.superscriptBaselineRatio)
        )
    }

    /// 아래 첨자: 글꼴 크기를 줄이고 베이스라인을 내린다.
    func applySubscript(
        to attributes: inout [NSAttributedString.Key: Any],
        shape: CoreHwp.HwpCharShape
    ) {
        let baseSize = HwpUnits.points(fromHwpUnit: shape.baseSize)
        let fontKey = kCTFontAttributeName as NSAttributedString.Key
        if let value = attributes[fontKey], CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() {
            let font = value as! CTFont // swiftlint:disable:this force_cast
            attributes[fontKey] = CTFontCreateCopyWithAttributes(
                font,
                CTFontGetSize(font) * Self.superscriptScale,
                nil,
                nil
            )
        }
        let baselineKey = HwpAttributedStringKey.glyphBaselineOffset
        let existing = (attributes[baselineKey] as? NSNumber)?.doubleValue ?? 0
        attributes[baselineKey] = NSNumber(
            value: existing - Double(baseSize * Self.subscriptBaselineRatio)
        )
    }
}

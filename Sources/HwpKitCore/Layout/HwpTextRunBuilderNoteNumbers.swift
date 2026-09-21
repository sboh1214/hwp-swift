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

/// 위/아래 첨자 글리프의 축소 배율과 베이스라인 이동 비율 (#204, 표 33 글자 모양의 첨자).
/// 축소 배율은 **글꼴 크기**(상대 크기 반영 후) 대비이고, 이동 비율은 **설정 글자 크기**
/// (`HwpCharShape.baseSize`, 상대 크기 반영 전) 대비다. 각주·미주 참조 번호는 다른 값
/// (`noteReferenceScale`·`noteReferenceBaselineRatio`)을 쓴다.
///
/// 한컴오피스 한글 12.30.0의 PDF 내보내기 벡터 좌표로 확정했다 (2026-09-15 함초롬바탕·Apple SD
/// 산돌고딕 Neo 10·20pt, 2026-09-21 두 글꼴 8·10·12·15·20·30·50·100pt 스윕 + 상대 크기 50·150% +
/// 각주·미주 참조 번호): 첨자 글리프는 글꼴 크기의 0.64배(10pt → 6.36·20pt → 12.84·100pt →
/// 63.96, 장치 0.12pt 양자화; 20pt 상대 50%는 6.36·150%는 19.20), 위 첨자는 설정 크기의 0.44배
/// 위(8pt 3.48·10pt 4.32~4.44·20pt 8.76·100pt 44.04; 상대 50%·150%도 20pt의 8.76~8.88), 아래
/// 첨자는 0.12배 아래(10pt 1.20·20pt 2.40·100pt 12.00)에 놓인다. 글자 위치(`faceLocation`)가
/// 옮긴 몫은 여기에 **더해진다** (`addScriptBaselineShift`). 종전 값 0.67·0.33·0.30은
/// `CharShapeProperty` 실물의 육안 추정이라 10pt에서 위 첨자가 1.1pt 낮고 아래 첨자가 1.8pt
/// 낮으며 글리프가 0.3pt 컸다.
extension HwpTextRunBuilder {
    /// 첨자 글꼴 크기 배율 (위·아래 첨자 공통, 글꼴 크기 대비)
    static let superscriptScale: CGFloat = 0.64
    /// 위 첨자 베이스라인 상승 비율 (설정 크기 대비)
    static let superscriptBaselineRatio: CGFloat = 0.44
    /// 아래 첨자 베이스라인 하강 비율 (설정 크기 대비)
    static let subscriptBaselineRatio: CGFloat = 0.12

    /// 각주·미주 참조 번호(본문 마커와 각주 내용의 위 첨자 번호, `applyNoteReferenceSuperscript`)의
    /// 축소 배율 — 글자 모양의 위 첨자와 **다른 규칙**이다. 한글 12.30 PDF 실측(2026-09-21,
    /// 함초롬바탕·함초롬돋움 8·10·15·20·30·40·50·60·100pt 본문 + 각주 내용 9pt): 번호 글꼴은
    /// 본문 글꼴 크기의 0.75배(8pt → 6.00·10pt → 7.56·20pt → 15.00·100pt → 75.00; 상대 크기
    /// 50%·150%의 20pt 본문은 7.56·22.56), 올림은 설정 크기의 0.21배(8pt 1.68·20pt 4.20·40pt
    /// 8.40·60pt 12.60·100pt 21.00; 상대 크기와 무관하게 4.20). 위 첨자 규칙(0.64·0.44)으로 그리면
    /// 10pt 본문의 번호가 1.2pt 작고 2.3pt 높다.
    static let noteReferenceScale: CGFloat = 0.75
    /// 각주·미주 참조 번호의 베이스라인 상승 비율 (설정 크기 대비)
    static let noteReferenceBaselineRatio: CGFloat = 0.21
}

/// 첨자 속성 — 표 33 위/아래 첨자와 각주·미주 참조 번호가 같은 두 키(`glyphBaselineOffset`·
/// `scriptBaselineOffset`)를 쓰되 배율·비율은 다르다 (#204).
extension HwpTextRunBuilder {
    /// 위 첨자 (표 33): 글꼴 크기를 0.64배로 줄이고 베이스라인을 설정 크기의 0.44배 올린다.
    func applySuperscript(
        to attributes: inout [NSAttributedString.Key: Any],
        shape: CoreHwp.HwpCharShape
    ) {
        applyScript(
            scale: Self.superscriptScale, baselineRatio: Self.superscriptBaselineRatio,
            to: &attributes, shape: shape
        )
    }

    /// 아래 첨자 (표 33): 글꼴 크기를 0.64배로 줄이고 베이스라인을 설정 크기의 0.12배 내린다.
    func applySubscript(
        to attributes: inout [NSAttributedString.Key: Any],
        shape: CoreHwp.HwpCharShape
    ) {
        applyScript(
            scale: Self.superscriptScale, baselineRatio: -Self.subscriptBaselineRatio,
            to: &attributes, shape: shape
        )
    }

    /// 각주·미주 참조 번호 (본문 마커·각주 내용의 위 첨자 번호): 글꼴 크기를 0.75배로 줄이고
    /// 베이스라인을 설정 크기의 0.21배 올린다 — 한글은 참조 번호에 글자 모양 위 첨자와 다른
    /// 규칙을 쓴다 (`noteReferenceScale`의 실측).
    func applyNoteReferenceSuperscript(
        to attributes: inout [NSAttributedString.Key: Any],
        shape: CoreHwp.HwpCharShape
    ) {
        applyScript(
            scale: Self.noteReferenceScale, baselineRatio: Self.noteReferenceBaselineRatio,
            to: &attributes, shape: shape
        )
    }

    /// 글꼴 크기를 `scale`배로 줄이고 베이스라인을 설정 크기 × `baselineRatio`(양수 = 위)만큼
    /// 옮긴다. 축소는 상대 크기가 반영된 글꼴 크기에, 이동은 상대 크기 반영 전 설정 크기에
    /// 거는 것이 한글과 같다 (20pt 상대 50% 위 첨자: 글리프 6.36pt·올림 8.88pt).
    private func applyScript(
        scale: CGFloat,
        baselineRatio: CGFloat,
        to attributes: inout [NSAttributedString.Key: Any],
        shape: CoreHwp.HwpCharShape
    ) {
        let baseSize = HwpUnits.points(fromHwpUnit: shape.baseSize)
        let fontKey = kCTFontAttributeName as NSAttributedString.Key
        if let value = attributes[fontKey], CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() {
            let font = value as! CTFont // swiftlint:disable:this force_cast
            attributes[fontKey] = CTFontCreateCopyWithAttributes(
                font,
                CTFontGetSize(font) * scale,
                nil,
                nil
            )
        }
        // 첨자 이동은 렌더가 반영하는 커스텀 키 (drawRun 글리프 세로 이동)로 싣는다 —
        // 도입 근거였던 "CTFramesetter는 kCTBaselineOffset을 무시한다"는 macOS 27.0에서
        // 거짓이다 (`HwpTextRunBuilder`의 같은 자리 주석). 다만 여기서 더하는 것은 커스텀
        // 키뿐이고 CT 키는 건드리지 않으므로, 첨자 이동 몫 자체는 상쇄되지 않는다.
        addScriptBaselineShift(Double(baseSize * baselineRatio), to: &attributes)
    }

    /// 첨자 이동량(양수 = 위)을 두 키에 누적한다 — 글리프를 옮기는 합산 키
    /// (`glyphBaselineOffset`, 글자 위치 몫이 먼저 들어 있을 수 있다)와 첨자 몫만 담는
    /// `scriptBaselineOffset` (#179). 뒤 키가 따로 있어야 장식선이 글자 위치는 무시하고
    /// 첨자만 따라갈 수 있다 — 합산 키에서는 두 몫을 되돌려 가를 수 없다.
    private func addScriptBaselineShift(
        _ shift: Double,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        for key in [
            HwpAttributedStringKey.glyphBaselineOffset,
            HwpAttributedStringKey.scriptBaselineOffset,
        ] {
            let existing = (attributes[key] as? NSNumber)?.doubleValue ?? 0
            attributes[key] = NSNumber(value: existing + shift)
        }
    }
}

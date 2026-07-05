import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation
import OSLog

public enum HwpAttributedStringKey {
    public static let underlineColor = NSAttributedString.Key("hwp.underlineColor")
    /// extended 컨트롤 문자(U+FFFC)가 가리키는 ctrlHeaderArray index (NSNumber).
    /// k번째 extended 컨트롤 문자 ↔ k번째 컨트롤 헤더 (noori/header-footer 픽스처 검증).
    public static let controlIndex = NSAttributedString.Key("hwp.controlIndex")
}

/// treatAsChar 개체의 줄 공간 예약 값 (CTRunDelegate refCon)
private final class HwpInlineObjectMetrics {
    let width: CGFloat
    let ascent: CGFloat

    init(width: CGFloat, ascent: CGFloat) {
        self.width = width
        self.ascent = ascent
    }
}

/// treatAsChar 개체 크기만큼 줄 공간을 예약하는 CTRunDelegate를 만든다.
private func makeInlineObjectRunDelegate(width: CGFloat, height: CGFloat) -> CTRunDelegate? {
    let metrics = HwpInlineObjectMetrics(width: width, ascent: height)
    var callbacks = CTRunDelegateCallbacks(
        version: kCTRunDelegateVersion1,
        dealloc: { pointer in
            Unmanaged<HwpInlineObjectMetrics>.fromOpaque(pointer).release()
        },
        getAscent: { pointer in
            Unmanaged<HwpInlineObjectMetrics>.fromOpaque(pointer)
                .takeUnretainedValue().ascent
        },
        getDescent: { _ in 0 },
        getWidth: { pointer in
            Unmanaged<HwpInlineObjectMetrics>.fromOpaque(pointer)
                .takeUnretainedValue().width
        }
    )
    return CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(metrics).toOpaque())
}

/// extended 컨트롤 마커 (U+FFFC) 대신 렌더할 텍스트 (각주 참조/자동 번호 등)
public struct HwpControlMarkerReplacement: Sendable, Hashable {
    public let text: String
    /// 위 첨자 (본문 각주 참조 번호, 표 143 bit 12)
    public let isSuperscript: Bool

    public init(text: String, isSuperscript: Bool = false) {
        self.text = text
        self.isSuperscript = isSuperscript
    }
}

public struct HwpTextRunBuilder {
    private let index: HwpIndex
    private let fontResolver: HwpFontResolver

    /// 위 첨자 번호의 글꼴 크기 배율/베이스라인 상승 배율 (기준 글자 크기 대비)
    static let superscriptScale: CGFloat = 0.6
    static let superscriptBaselineRatio: CGFloat = 0.33

    public init(index: HwpIndex, fontResolver: HwpFontResolver) {
        self.index = index
        self.fontResolver = fontResolver
    }

    /// controlReplacements: extended 컨트롤 ordinal (controlIndex) → 마커 대신
    /// 방출할 텍스트. 각주 참조 번호 (본문)와 자동 번호 (각주 문단 첫머리) 치환에
    /// 쓴다. 치환된 run은 폭 0 예약 대신 실제 글리프 폭을 차지한다.
    public func build(
        paragraph: CoreHwp.HwpParagraph,
        controlReplacements: [Int: HwpControlMarkerReplacement] = [:]
    ) -> NSAttributedString {
        let units = paragraph.paraText?.charArray ?? []
        guard !units.isEmpty else { return NSAttributedString(string: "") }

        let output = NSMutableAttributedString()
        var chunk = Chunk(shapeId: activeShapeId(at: 0, in: paragraph.paraCharShape), script: nil)
        // startingIndex는 원본 WCHAR 스트림 위치 기준: inline/extended 컨트롤은
        // charArray에서 1개 요소지만 스트림에서는 8 WCHAR를 차지한다.
        var wcharPosition: UInt32 = 0
        var pendingHighSurrogate: UInt16?
        var extendedOrdinal = 0

        for hwpChar in units {
            let position = wcharPosition
            wcharPosition += wcharLength(of: hwpChar)

            let text = string(from: hwpChar, pendingHighSurrogate: &pendingHighSurrogate)
            guard !text.isEmpty else { continue }

            let shapeId = activeShapeId(at: position, in: paragraph.paraCharShape)
            if hwpChar.type == .char {
                accumulate(text, shapeId: shapeId, into: &chunk, paragraph: paragraph, to: output)
                continue
            }

            // 컨트롤 문자: 선행 잔여 문자(lone surrogate)는 일반 chunk로 보내고,
            // U+FFFC는 컨트롤 index attribute를 단 별도 run으로 낸다.
            let prefix = String(text.dropLast())
            if !prefix.isEmpty {
                accumulate(prefix, shapeId: shapeId, into: &chunk, paragraph: paragraph, to: output)
            }
            append(chunk, paragraph: paragraph, to: output)
            chunk = Chunk(shapeId: shapeId, script: nil)

            let controlIndex: Int? = hwpChar.type == .extended ? extendedOrdinal : nil
            if hwpChar.type == .extended { extendedOrdinal += 1 }
            appendControlMarker(
                controlIndex: controlIndex,
                shapeId: shapeId,
                paragraph: paragraph,
                replacement: controlIndex.flatMap { controlReplacements[$0] },
                to: output
            )
        }

        if let lone = pendingHighSurrogate {
            chunk.text += String(decoding: [lone], as: UTF16.self)
        }
        append(chunk, paragraph: paragraph, to: output)

        // 문단 스타일 (정렬/들여쓰기/줄간격)을 문자열에 실어 렌더 (drawText 재조판)가
        // 측정 레이아웃과 같은 조판을 쓰게 한다.
        if output.length > 0,
           let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))
           ?? index.paraShape(id: 0)
        {
            output.addAttribute(
                kCTParagraphStyleAttributeName as NSAttributedString.Key,
                value: HwpParagraphLayout.paragraphStyle(
                    for: paraShape,
                    attributedString: output
                ),
                range: NSRange(location: 0, length: output.length)
            )
        }
        return output
    }
}

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
}

private extension HwpTextRunBuilder {
    struct Chunk {
        var shapeId: UInt32
        var script: HwpScript?
        var text = ""
    }

    /// 일반 문자를 현재 chunk에 합치거나, 모양/스크립트가 바뀌면 chunk를 내보낸다.
    func accumulate(
        _ text: String,
        shapeId: UInt32,
        into chunk: inout Chunk,
        paragraph: CoreHwp.HwpParagraph,
        to output: NSMutableAttributedString
    ) {
        let script = detectScript(in: text)
        if chunk.script == nil {
            chunk.shapeId = shapeId
            chunk.script = script
        } else if chunk.shapeId != shapeId || chunk.script != script {
            append(chunk, paragraph: paragraph, to: output)
            chunk = Chunk(shapeId: shapeId, script: script)
        }
        chunk.text += text
    }

    func append(
        _ chunk: Chunk,
        paragraph: CoreHwp.HwpParagraph,
        to output: NSMutableAttributedString
    ) {
        guard !chunk.text.isEmpty, let script = chunk.script else { return }
        let shape = resolvedShape(id: chunk.shapeId, paragraph: paragraph)
        let attributed = NSAttributedString(
            string: chunk.text,
            attributes: attributes(for: shape, script: script)
        )
        output.append(attributed)
    }

    /// U+FFFC 컨트롤 마커 run을 내보낸다.
    ///
    /// extended 컨트롤이면 controlIndex attribute를 달고, run delegate로 줄 공간을
    /// 조정한다: treatAsChar 개체는 개체 크기만큼 예약 (줄 높이 보정 — 표는 flow
    /// 배치를 유지하므로 제외), 그 밖의 extended 컨트롤(구역/단/머리말 정의 등)은
    /// 한글과 같이 폭 0으로 처리해 글리프 공간을 차지하지 않게 한다.
    func appendControlMarker(
        controlIndex: Int?,
        shapeId: UInt32,
        paragraph: CoreHwp.HwpParagraph,
        replacement: HwpControlMarkerReplacement? = nil,
        to output: NSMutableAttributedString
    ) {
        let shape = resolvedShape(id: shapeId, paragraph: paragraph)

        // 치환 텍스트가 있으면 마커 대신 실제 번호 run을 방출한다.
        if let replacement, !replacement.text.isEmpty {
            let script = detectScript(in: replacement.text)
            var textAttributes = attributes(for: shape, script: script)
            if replacement.isSuperscript {
                applySuperscript(to: &textAttributes, shape: shape)
            }
            if let controlIndex {
                textAttributes[HwpAttributedStringKey.controlIndex] = NSNumber(
                    value: controlIndex
                )
            }
            output.append(NSAttributedString(
                string: replacement.text,
                attributes: textAttributes
            ))
            return
        }

        var markerAttributes = attributes(for: shape, script: .english)
        if let controlIndex {
            markerAttributes[HwpAttributedStringKey.controlIndex] = NSNumber(value: controlIndex)
            let size = inlineObjectSize(controlIndex: controlIndex, paragraph: paragraph)
                ?? .zero
            if size.height > 0 {
                markerAttributes[HwpAttributedStringKey.inlineObjectHeight] = NSNumber(
                    value: Double(size.height)
                )
            }
            if let delegate = makeInlineObjectRunDelegate(
                width: size.width,
                height: size.height
            ) {
                markerAttributes[kCTRunDelegateAttributeName as NSAttributedString.Key] = delegate
            }
        }
        output.append(NSAttributedString(string: "\u{FFFC}", attributes: markerAttributes))
    }

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
        let baselineKey = kCTBaselineOffsetAttributeName as NSAttributedString.Key
        let existing = (attributes[baselineKey] as? NSNumber)?.doubleValue ?? 0
        attributes[baselineKey] = NSNumber(
            value: existing + Double(baseSize * Self.superscriptBaselineRatio)
        )
    }

    /// controlIndex번째 컨트롤이 treatAsChar 개체면 예약할 크기 (pt).
    func inlineObjectSize(
        controlIndex: Int,
        paragraph: CoreHwp.HwpParagraph
    ) -> CGSize? {
        guard let ctrls = paragraph.ctrlHeaderArray,
              ctrls.indices.contains(controlIndex)
        else { return nil }

        let commonProperty: CoreHwp.HwpCommonCtrlProperty?
        let components: [CoreHwp.HwpShapeComponent]
        switch ctrls[controlIndex] {
        case let .genShapeObject(genShape):
            commonProperty = genShape.commonCtrlProperty
            components = genShape.shapeComponentArray
        case let .shape(shape),
             let .line(shape),
             let .rectangle(shape),
             let .ellipse(shape),
             let .arc(shape),
             let .polygon(shape),
             let .curve(shape),
             let .equation(shape),
             let .equationLegacy(shape),
             let .picture(shape),
             let .ole(shape),
             let .container(shape):
            commonProperty = shape.commonCtrlProperty
            components = shape.shapeComponentArray
        default:
            return nil
        }
        guard let commonProperty, commonProperty.propertyInfo.treatAsChar else { return nil }

        var width = HwpUnits.points(fromHwpUnitU: commonProperty.width)
        var height = HwpUnits.points(fromHwpUnitU: commonProperty.height)
        if width <= 0 || height <= 0, let detail = components.first?.detail {
            if width <= 0 { width = HwpUnits.points(fromHwpUnitU: detail.currentWidth) }
            if height <= 0 { height = HwpUnits.points(fromHwpUnitU: detail.currentHeight) }
        }
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    func attributes(
        for shape: CoreHwp.HwpCharShape,
        script: HwpScript
    ) -> [NSAttributedString.Key: Any] {
        let slot = script.slotIndex
        let baseSize = HwpUnits.points(fromHwpUnit: shape.baseSize)
        let size = baseSize * (CGFloat(value(at: slot, in: shape.faceScaleX, default: 100)) / 100)
        let faceId = UInt32(value(at: slot, in: shape.faceId, default: 0))
        let faceName = index.faceName(for: faceId, script: script)?.faceName ?? "Helvetica"
        var font = fontResolver.resolve(faceName: faceName, script: script, size: size)
        font = copy(font, adding: symbolicTraits(for: shape.property))

        let spacing = CGFloat(value(at: slot, in: shape.faceSpacing, default: 0))
        let location = CGFloat(value(at: slot, in: shape.faceLocation, default: 0))
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: shape.faceColor.cgColor,
            kCTKernAttributeName as NSAttributedString.Key: NSNumber(
                value: Double(spacing * baseSize / 100)
            ),
            kCTBaselineOffsetAttributeName as NSAttributedString.Key: NSNumber(
                value: Double(location * baseSize / 100)
            ),
        ]

        if shape.property.underlineType != .none {
            // NSUnderlineStyle.single = 1; no AppKit/UIKit in HwpKitCore
            attributes[.underlineStyle] = NSNumber(value: 1)
            attributes[HwpAttributedStringKey.underlineColor] = shape.underlineColor.cgColor
        }
        if shape.property.strikethrough != 0 {
            attributes[.strikethroughStyle] = NSNumber(value: 1) // NSUnderlineStyle.single = 1
        }
        return attributes
    }

    func resolvedShape(id: UInt32, paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpCharShape {
        if let shape = index.charShape(id: id) { return shape }
        os_log(
            "HwpTextRunBuilder missing char shape: paraId=%{public}u shapeId=%{public}u",
            type: .default,
            paragraph.paraHeader.paraId,
            id
        )
        return CoreHwp.HwpCharShape()
    }

    func activeShapeId(at position: UInt32, in paraCharShape: CoreHwp.HwpParaCharShape) -> UInt32 {
        var active: UInt32 = paraCharShape.shapeId.first ?? 0
        for (index, start) in paraCharShape.startingIndex.enumerated() {
            guard start <= position else { break }
            active = value(at: index, in: paraCharShape.shapeId, default: active)
        }
        return active
    }

    func detectScript(in text: String) -> HwpScript {
        text.unicodeScalars.first.map(HwpScript.detect(from:)) ?? .english
    }

    func wcharLength(of hwpChar: CoreHwp.HwpChar) -> UInt32 {
        switch hwpChar.type {
        case .char: 1
        case .inline, .extended: 8
        }
    }

    func string(from hwpChar: CoreHwp.HwpChar, pendingHighSurrogate: inout UInt16?) -> String {
        switch hwpChar.type {
        case .char:
            let unit = hwpChar.value
            if let high = pendingHighSurrogate {
                pendingHighSurrogate = nil
                if UTF16.isTrailSurrogate(unit) {
                    return String(decoding: [high, unit], as: UTF16.self)
                }
                let lone = String(decoding: [high], as: UTF16.self)
                return lone + string(from: hwpChar, pendingHighSurrogate: &pendingHighSurrogate)
            }
            if UTF16.isLeadSurrogate(unit) {
                pendingHighSurrogate = unit
                return ""
            }
            return String(decoding: [unit], as: UTF16.self)
        case .inline, .extended:
            if let lone = pendingHighSurrogate {
                pendingHighSurrogate = nil
                return String(decoding: [lone], as: UTF16.self) + "\u{FFFC}"
            }
            return "\u{FFFC}"
        }
    }

    func symbolicTraits(for property: CoreHwp.HwpCharShapeProperty) -> CTFontSymbolicTraits {
        var traits = CTFontSymbolicTraits()
        if property.isBold { traits.insert(.traitBold) }
        if property.isItalic { traits.insert(.traitItalic) }
        return traits
    }

    func copy(_ font: CTFont, adding traits: CTFontSymbolicTraits) -> CTFont {
        guard !traits.isEmpty,
              let descriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(
                  CTFontCopyFontDescriptor(font),
                  traits,
                  traits
              )
        else { return font }
        return CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(font), nil)
    }

    func value<T>(at index: Int, in array: [T], default fallback: T) -> T {
        array.indices.contains(index) ? array[index] : fallback
    }
}

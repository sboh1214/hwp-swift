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

public struct HwpTextRunBuilder {
    private let index: HwpIndex
    private let fontResolver: HwpFontResolver

    public init(index: HwpIndex, fontResolver: HwpFontResolver) {
        self.index = index
        self.fontResolver = fontResolver
    }

    public func build(paragraph: CoreHwp.HwpParagraph) -> NSAttributedString {
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
                value: HwpParagraphLayout.paragraphStyle(for: paraShape),
                range: NSRange(location: 0, length: output.length)
            )
        }
        return output
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
        to output: NSMutableAttributedString
    ) {
        let shape = resolvedShape(id: shapeId, paragraph: paragraph)
        var markerAttributes = attributes(for: shape, script: .english)
        if let controlIndex {
            markerAttributes[HwpAttributedStringKey.controlIndex] = NSNumber(value: controlIndex)
            let size = inlineObjectSize(controlIndex: controlIndex, paragraph: paragraph)
                ?? .zero
            if let delegate = makeInlineObjectRunDelegate(
                width: size.width,
                height: size.height
            ) {
                markerAttributes[kCTRunDelegateAttributeName as NSAttributedString.Key] = delegate
            }
        }
        output.append(NSAttributedString(string: "\u{FFFC}", attributes: markerAttributes))
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

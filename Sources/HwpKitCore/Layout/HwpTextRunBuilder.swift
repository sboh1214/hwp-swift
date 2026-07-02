import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation
import OSLog

public enum HwpAttributedStringKey {
    public static let underlineColor = NSAttributedString.Key("hwp.underlineColor")
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

        for (position, hwpChar) in units.enumerated() {
            let text = string(from: hwpChar)
            guard !text.isEmpty else { continue }

            let shapeId = activeShapeId(at: UInt32(position), in: paragraph.paraCharShape)
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

        append(chunk, paragraph: paragraph, to: output)
        return output
    }
}

private extension HwpTextRunBuilder {
    struct Chunk {
        var shapeId: UInt32
        var script: HwpScript?
        var text = ""
    }

    func append(_ chunk: Chunk, paragraph: CoreHwp.HwpParagraph, to output: NSMutableAttributedString) {
        guard !chunk.text.isEmpty, let script = chunk.script else { return }
        let shape = resolvedShape(id: chunk.shapeId, paragraph: paragraph)
        output.append(NSAttributedString(string: chunk.text, attributes: attributes(for: shape, script: script)))
    }

    func attributes(for shape: CoreHwp.HwpCharShape, script: HwpScript) -> [NSAttributedString.Key: Any] {
        let slot = script.slotIndex
        let baseSize = HwpUnits.points(fromHwpUnit: shape.baseSize)
        let size = baseSize * (CGFloat(value(at: slot, in: shape.faceScaleX, default: 100)) / 100)
        let faceId = UInt32(value(at: slot, in: shape.faceId, default: 0))
        let faceName = index.faceName(for: faceId, script: script)?.faceName ?? "Helvetica"
        var font = fontResolver.resolve(faceName: faceName, script: script, size: size)
        font = copy(font, adding: symbolicTraits(for: shape.property))

        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: shape.faceColor.cgColor,
            kCTKernAttributeName as NSAttributedString.Key: NSNumber(
                value: Double(CGFloat(value(at: slot, in: shape.faceSpacing, default: 0)) * baseSize / 100)
            ),
            kCTBaselineOffsetAttributeName as NSAttributedString.Key: NSNumber(
                value: Double(CGFloat(value(at: slot, in: shape.faceLocation, default: 0)) * baseSize / 100)
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
        for (index, start) in paraCharShape.startingIndex.enumerated() where start <= position {
            active = value(at: index, in: paraCharShape.shapeId, default: active)
        }
        return active
    }

    func detectScript(in text: String) -> HwpScript {
        text.unicodeScalars.first.map(HwpScript.detect(from:)) ?? .english
    }

    func string(from hwpChar: CoreHwp.HwpChar) -> String {
        switch hwpChar.type {
        case .char:
            String(decoding: [hwpChar.value], as: UTF16.self)
        case .inline, .extended:
            "\u{FFFC}"
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

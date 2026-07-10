import CoreGraphics
@preconcurrency import CoreHwp
import CoreText
import Foundation
import OSLog

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
    /// 아래 첨자 베이스라인 하강 배율
    static let subscriptBaselineRatio: CGFloat = 0.15

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
        let memoAnchorRanges = Self.memoAnchorRanges(in: paragraph)

        for hwpChar in units {
            let position = wcharPosition
            wcharPosition += wcharLength(of: hwpChar)

            let text = string(from: hwpChar, pendingHighSurrogate: &pendingHighSurrogate)
            guard !text.isEmpty else { continue }

            let shapeId = activeShapeId(at: position, in: paragraph.paraCharShape)
            let trackMark = Self.trackChangeMark(at: position, in: paragraph)
            let memoAnchor = memoAnchorRanges.contains { $0.contains(position) }
            if hwpChar.type == .char {
                accumulate(
                    text, shapeId: shapeId, trackMark: trackMark, memoAnchor: memoAnchor,
                    into: &chunk, paragraph: paragraph, to: output
                )
                continue
            }

            // 컨트롤 문자: 선행 잔여 문자(lone surrogate)는 일반 chunk로 보내고,
            // U+FFFC는 컨트롤 index attribute를 단 별도 run으로 낸다.
            let prefix = String(text.dropLast())
            if !prefix.isEmpty {
                accumulate(
                    prefix, shapeId: shapeId, trackMark: trackMark, memoAnchor: memoAnchor,
                    into: &chunk, paragraph: paragraph, to: output
                )
            }
            append(chunk, paragraph: paragraph, to: output)
            chunk = Chunk(shapeId: shapeId, script: nil)
            emitControl(
                hwpChar, shapeId: shapeId, paragraph: paragraph,
                controlReplacements: controlReplacements,
                extendedOrdinal: &extendedOrdinal, to: output
            )
        }

        if let lone = pendingHighSurrogate {
            chunk.text += String(decoding: [lone], as: UTF16.self)
        }
        append(chunk, paragraph: paragraph, to: output)
        attachParagraphStyle(to: output, paragraph: paragraph)
        return output
    }
}

private extension HwpTextRunBuilder {
    // 컨트롤 문자 하나를 마커 run으로 내보낸다 (extended ordinal 전진 포함).
    // swiftlint:disable:next function_parameter_count
    func emitControl(
        _ hwpChar: CoreHwp.HwpChar,
        shapeId: UInt32,
        paragraph: CoreHwp.HwpParagraph,
        controlReplacements: [Int: HwpControlMarkerReplacement],
        extendedOrdinal: inout Int,
        to output: NSMutableAttributedString
    ) {
        let controlIndex: Int? = hwpChar.type == .extended ? extendedOrdinal : nil
        if hwpChar.type == .extended {
            extendedOrdinal += 1
        }
        appendControlMarker(
            controlIndex: controlIndex,
            shapeId: shapeId,
            paragraph: paragraph,
            replacement: controlIndex.flatMap { controlReplacements[$0] },
            inlineValue: hwpChar.type == .inline ? hwpChar.value : nil,
            to: output
        )
    }

    /// 문단 스타일 (정렬/들여쓰기/줄간격)을 문자열에 실어 렌더 (drawText 재조판)가
    /// 측정 레이아웃과 같은 조판을 쓰게 한다.
    func attachParagraphStyle(
        to output: NSMutableAttributedString,
        paragraph: CoreHwp.HwpParagraph
    ) {
        guard output.length > 0,
              let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId))
              ?? index.paraShape(id: 0)
        else { return }
        output.addAttribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            value: HwpParagraphLayout.paragraphStyle(
                for: paraShape,
                attributedString: output
            ),
            range: NSRange(location: 0, length: output.length)
        )
    }
}

private extension HwpTextRunBuilder {
    struct Chunk {
        var shapeId: UInt32
        var script: HwpScript?
        var text = ""
        /// 변경 추적 마크 (0 없음 / 16 삽입 / 17 삭제 — PARA_RANGE_TAG kind)
        var trackMark: UInt32 = 0
        /// 메모 (댓글) 앵커 범위 안 — 연녹색 강조 (한글.app 편집 뷰)
        var memoAnchor = false
    }

    /// 일반 문자를 현재 chunk에 합치거나, 모양/스크립트/변경 마크가 바뀌면
    /// chunk를 내보낸다.
    func accumulate(
        _ text: String,
        shapeId: UInt32,
        trackMark: UInt32 = 0,
        memoAnchor: Bool = false,
        into chunk: inout Chunk,
        paragraph: CoreHwp.HwpParagraph,
        to output: NSMutableAttributedString
    ) {
        let script = detectScript(in: text)
        if chunk.script == nil {
            chunk.shapeId = shapeId
            chunk.script = script
            chunk.trackMark = trackMark
            chunk.memoAnchor = memoAnchor
        } else if chunk.shapeId != shapeId || chunk.script != script
            || chunk.trackMark != trackMark || chunk.memoAnchor != memoAnchor
        {
            append(chunk, paragraph: paragraph, to: output)
            chunk = Chunk(
                shapeId: shapeId, script: script,
                trackMark: trackMark, memoAnchor: memoAnchor
            )
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
        var chunkAttributes = attributes(for: shape, script: script)
        applyTrackChangeMark(chunk.trackMark, to: &chunkAttributes)
        if chunk.memoAnchor,
           chunkAttributes[HwpAttributedStringKey.shadeColor] == nil
        {
            // 메모 앵커: 한글.app처럼 연녹색 배경 강조 (음영과 같은 상자 그리기)
            chunkAttributes[HwpAttributedStringKey.shadeColor] =
                HwpMemoPanelPainter.anchorFillColor
        }
        let attributed = NSAttributedString(
            string: chunk.text,
            attributes: chunkAttributes
        )
        output.append(attributed)
    }

    /// U+FFFC 컨트롤 마커 run을 내보낸다.
    ///
    /// extended 컨트롤이면 controlIndex attribute를 달고, run delegate로 줄 공간을
    /// 조정한다: treatAsChar 개체 (표 포함)는 개체 크기만큼 예약 (줄 높이 보정),
    /// 그 밖의 extended 컨트롤(구역/단/머리말 정의 등)은
    /// 한글과 같이 폭 0으로 처리해 글리프 공간을 차지하지 않게 한다.
    func appendControlMarker(
        controlIndex: Int?,
        shapeId: UInt32,
        paragraph: CoreHwp.HwpParagraph,
        replacement: HwpControlMarkerReplacement? = nil,
        inlineValue: CoreHwp.WCHAR? = nil,
        to output: NSMutableAttributedString
    ) {
        let shape = resolvedShape(id: shapeId, paragraph: paragraph)

        // 탭 (inline 코드 9)은 실제 탭으로 방출한다 (CT 탭 스톱 조판).
        if inlineValue == 9 {
            output.append(NSAttributedString(
                string: "\t",
                attributes: attributes(for: shape, script: .english)
            ))
            return
        }

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
        var size = CGSize.zero
        if let controlIndex {
            markerAttributes[HwpAttributedStringKey.controlIndex] = NSNumber(value: controlIndex)
            size = inlineObjectSize(controlIndex: controlIndex, paragraph: paragraph)
                ?? .zero
            if size.height > 0 {
                markerAttributes[HwpAttributedStringKey.inlineObjectHeight] = NSNumber(
                    value: Double(size.height)
                )
            }
        }
        // 개체가 아닌 마커 (필드 시작/끝·메모 앵커 등)도 폭 0 delegate를 달아
        // U+FFFC tofu 글리프가 보이지 않게 한다 (한글.app: 무형 문자)
        if let delegate = makeInlineObjectRunDelegate(
            width: size.width,
            height: size.height
        ) {
            markerAttributes[kCTRunDelegateAttributeName as NSAttributedString.Key] = delegate
        }
        output.append(NSAttributedString(string: "\u{FFFC}", attributes: markerAttributes))
    }

    func attributes(
        for shape: CoreHwp.HwpCharShape,
        script: HwpScript
    ) -> [NSAttributedString.Key: Any] {
        let slot = script.slotIndex
        let baseSize = HwpUnits.points(fromHwpUnit: shape.baseSize)
        // 상대 크기 (표 33)가 실제 글자 크기 배율, 장평 (faceScaleX)은 가로 스케일
        let relativeSize = CGFloat(value(at: slot, in: shape.faceRelativeSize, default: 100))
        let size = baseSize * relativeSize / 100
        let faceId = UInt32(value(at: slot, in: shape.faceId, default: 0))
        let faceName = index.faceName(for: faceId, script: script)?.faceName ?? "Helvetica"
        var font = fontResolver.resolve(faceName: faceName, script: script, size: size)
        font = copy(font, adding: symbolicTraits(for: shape.property))
        let scaleX = CGFloat(value(at: slot, in: shape.faceScaleX, default: 100)) / 100
        if scaleX != 1 {
            // 기울임 폴백 매트릭스와 겹칠 수 있으므로 기존 매트릭스에 합성한다
            var matrix = CTFontGetMatrix(font)
                .concatenating(CGAffineTransform(scaleX: scaleX, y: 1))
            font = CTFontCreateCopyWithAttributes(font, 0, &matrix, nil)
        }

        let spacing = CGFloat(value(at: slot, in: shape.faceSpacing, default: 0))
        let location = CGFloat(value(at: slot, in: shape.faceLocation, default: 0))
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: shape.faceColor.cgColor,
            kCTKernAttributeName as NSAttributedString.Key: NSNumber(
                value: Double(spacing * size / 100)
            ),
            kCTBaselineOffsetAttributeName as NSAttributedString.Key: NSNumber(
                value: Double(location * size / 100)
            ),
        ]

        applyShapeDecorations(to: &attributes, shape: shape, size: size)
        return attributes
    }

    func resolvedShape(id: UInt32, paragraph: CoreHwp.HwpParagraph) -> CoreHwp.HwpCharShape {
        if let shape = index.charShape(id: id) {
            return shape
        }
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
        if property.isBold {
            traits.insert(.traitBold)
        }
        if property.isItalic {
            traits.insert(.traitItalic)
        }
        return traits
    }

    func copy(_ font: CTFont, adding traits: CTFontSymbolicTraits) -> CTFont {
        guard !traits.isEmpty else { return font }
        if let descriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(
            CTFontCopyFontDescriptor(font),
            traits,
            traits
        ) {
            return CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(font), nil)
        }
        // 요청한 조합 페이스가 없는 폰트 (한글 명조 등): 볼드만 먼저 시도하고,
        // 이탤릭은 기울임 매트릭스로 근사한다 (한글.app 동작).
        var result = font
        if traits.contains(.traitBold),
           let boldDescriptor = CTFontDescriptorCreateCopyWithSymbolicTraits(
               CTFontCopyFontDescriptor(result),
               .traitBold,
               .traitBold
           )
        {
            result = CTFontCreateWithFontDescriptor(boldDescriptor, CTFontGetSize(result), nil)
        }
        if traits.contains(.traitItalic) {
            var matrix = CTFontGetMatrix(result)
            matrix.c += 0.22
            result = CTFontCreateCopyWithAttributes(result, 0, &matrix, nil)
        }
        return result
    }

    func value<T>(at index: Int, in array: [T], default fallback: T) -> T {
        array.indices.contains(index) ? array[index] : fallback
    }
}

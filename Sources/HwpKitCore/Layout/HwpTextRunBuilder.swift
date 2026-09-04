import CoreGraphics
import CoreHwp
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
    let index: HwpIndex
    let fontResolver: HwpFontResolver
    /// 상대 크기 기준 해석기 — treatAsChar 개체의 줄 공간 예약이 paint 쪽
    /// (HwpPaginator.objectSize)과 같은 크기를 쓰게 한다. 없으면 절대값 해석.
    let sizeResolver: HwpObjectSizeResolver?
    /// 글자 모양별 속성 사전 캐시 — 같은 문서(`index`)·같은 `fontResolver`를 쓰는
    /// 빌더끼리 공유한다 (소유는 `HwpPaginator`). nil이면 매번 새로 계산한다.
    let attributeCache: HwpTextAttributeCache?

    public init(
        index: HwpIndex,
        fontResolver: HwpFontResolver,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) {
        self.init(
            index: index, fontResolver: fontResolver,
            sizeResolver: sizeResolver, attributeCache: nil
        )
    }

    /// 캐시를 주입하는 모듈 내부용 init — 캐시는 문서 단위 소유라 모듈 밖으로
    /// 열지 않는다 (`HwpTextAttributeCache` 참조).
    init(
        index: HwpIndex,
        fontResolver: HwpFontResolver,
        sizeResolver: HwpObjectSizeResolver? = nil,
        attributeCache: HwpTextAttributeCache?
    ) {
        self.index = index
        self.fontResolver = fontResolver
        self.sizeResolver = sizeResolver
        self.attributeCache = attributeCache
    }

    /// controlReplacements: extended 컨트롤 ordinal (controlIndex) → 마커 대신
    /// 방출할 텍스트. 각주 참조 번호 (본문)와 자동 번호 (각주 문단 첫머리) 치환에
    /// 쓴다. 치환된 run은 폭 0 예약 대신 실제 글리프 폭을 차지한다.
    public func build(
        paragraph: CoreHwp.HwpParagraph,
        controlReplacements: [Int: HwpControlMarkerReplacement] = [:],
        maxCharacters: Int = .max
    ) -> NSAttributedString {
        // 입력 문자를 상한까지만 처리해 거대 문단 build 비용을 제한한다 (메모 표시
        // 예산 등). 음수 클램프와 서로게이트 경계 처리는 surrogateSafePrefix에 있다.
        let units = surrogateSafePrefix(paragraph.paraText?.charArray ?? [], upTo: maxCharacters)
        guard !units.isEmpty else { return NSAttributedString(string: "") }

        let output = NSMutableAttributedString()
        appendBulletHeading(for: paragraph, to: output)
        // 글자 모양/변경추적/메모 앵커를 문자마다 처음부터 재스캔하면 문단당
        // O(문자×run)이 된다 — position(wcharPosition)이 단조 증가하므로 각
        // 커서를 앞으로만 밀어 sweep한다 (#10, #11). 결과는 전수 스캔과 동일.
        let shapeStarts = paragraph.paraCharShape.startingIndex
        let shapeIds = paragraph.paraCharShape.shapeId
        var shapeSweep = 0
        var activeShape = shapeIds.first ?? 0
        let trackIntervals = Self.trackChangeIntervals(in: paragraph)
        var trackCursor = 0
        let memoAnchorRanges = Self.memoAnchorRanges(in: paragraph)
        var memoCursor = 0

        var chunk = Chunk(shapeId: activeShape, script: nil)
        // startingIndex는 원본 WCHAR 스트림 위치 기준: inline/extended 컨트롤은
        // charArray에서 1개 요소지만 스트림에서는 8 WCHAR를 차지한다.
        var wcharPosition: UInt32 = 0
        var pendingHighSurrogate: UInt16?
        var extendedOrdinal = 0
        // 하이퍼링크(%hlk) 필드가 감싸는 attributed 범위 추적. 필드는 코드 3
        // 시작 ~ 코드 4 끝으로 LIFO 중첩되므로 필드 depth와 depth별 하이퍼링크
        // 스택을 함께 둬, 중첩 필드의 끝 마커가 바깥 링크를 조기 종료하지
        // 못하게 한다 — 시작 마커 뒤부터 매칭 끝 마커 전까지 속성을 단다 (#1·#2).
        var fieldDepth = 0
        var hyperlinkStack: [HyperlinkFrame] = []
        // 직전에 방출한 문자가 한 줄 끝(U+000A)인지 — 문단 끝 앵커 판정용 (아래).
        var pendingEmptyLastLine = false

        for hwpChar in units {
            let position = wcharPosition
            wcharPosition += wcharLength(of: hwpChar)

            let text = emittedText(
                of: hwpChar, pendingHighSurrogate: &pendingHighSurrogate,
                followsLineBreak: &pendingEmptyLastLine
            )
            guard !text.isEmpty else { continue }

            while shapeSweep < shapeStarts.count, shapeStarts[shapeSweep] <= position {
                activeShape = value(at: shapeSweep, in: shapeIds, default: activeShape)
                shapeSweep += 1
            }
            let shapeId = activeShape
            while trackCursor < trackIntervals.count, trackIntervals[trackCursor].end <= position {
                trackCursor += 1
            }
            let trackMark: UInt32 = trackCursor < trackIntervals.count
                && trackIntervals[trackCursor].start <= position
                && position < trackIntervals[trackCursor].end
                ? trackIntervals[trackCursor].kind : 0
            let memoAnchor = memoAnchor(at: position, in: memoAnchorRanges, cursor: &memoCursor)
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
            // 필드 끝(inline 4): 이 depth에서 연 필드를 닫는다. 하이퍼링크가
            // 이 depth에서 시작했을 때만 링크 속성을 확정해, 중첩 필드의 끝
            // 마커가 바깥 하이퍼링크를 조기 종료하지 않게 한다 (#1). 끝 마커
            // 직전까지가 링크 텍스트라 emitControl 전에 적용한다 (#2).
            if hwpChar.type == .inline, hwpChar.value == 4 {
                if let top = hyperlinkStack.last, top.depth == fieldDepth {
                    if output.length > top.start {
                        output.addAttribute(
                            HwpAttributedStringKey.hyperlink, value: top.url,
                            range: NSRange(location: top.start, length: output.length - top.start)
                        )
                    }
                    hyperlinkStack.removeLast()
                }
                if fieldDepth > 0 {
                    fieldDepth -= 1
                }
            }
            let hyperlinkOrdinal = extendedOrdinal
            emitControl(
                hwpChar, shapeId: shapeId, paragraph: paragraph,
                controlReplacements: controlReplacements,
                extendedOrdinal: &extendedOrdinal, to: output
            )
            // 필드 시작(코드 3): depth++. 하이퍼링크면 그 depth로 스택에 쌓아
            // 매칭 끝 마커에서만 닫히게 한다 (#1). 시작 마커 뒤부터 링크 범위
            // (#2). 표/이미지 등 비-필드 extended(코드 3 아님)는 끝 짝이 없어 제외.
            if hwpChar.type == .extended, hwpChar.value == 3 {
                fieldDepth += 1
                if let ctrls = paragraph.ctrlHeaderArray,
                   hyperlinkOrdinal < ctrls.count,
                   case let .hyperLink(link) = ctrls[hyperlinkOrdinal], !link.url.isEmpty
                {
                    hyperlinkStack.append(HyperlinkFrame(
                        depth: fieldDepth,
                        start: output.length,
                        url: HwpHyperlinkURL.displayURL(link.url)
                    ))
                }
            }
        }

        if let lone = pendingHighSurrogate {
            chunk.text += String(decoding: [lone], as: UTF16.self)
        }
        append(chunk, paragraph: paragraph, to: output)
        attachParagraphStyle(to: output, paragraph: paragraph)
        return output
    }
}

extension HwpTextRunBuilder {
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

    /// 문단 스타일 (정렬/들여쓰기/줄간격)을 문자열에 실어 렌더 (drawText 재조판)와
    /// 측정 (`HwpParagraphLayout.layout`)이 같은 조판을 쓰게 한다.
    ///
    /// **shape 해석은 `paraShapeOrDefault`다** — 측정 경로
    /// (`HwpParagraphMeasurer`·`HwpPageChromeBuilder`)와 같은 폴백이어야 한다.
    /// `paraShape(for:)`(nil 가능)를 쓰던 시절에는 paraShape 표가 통째로 빈 문서에서
    /// 부착은 통째로 생략되는데 측정만 기본 shape로 조판해, 측정·렌더가 갈렸다.
    /// 측정이 부착본을 그대로 framesetting하게 된 뒤(#80 조각 3)로는 그 비대칭이
    /// 이론이 아니라 **측정 결과 자체**를 바꾸므로 여기서 닫는다.
    func attachParagraphStyle(
        to output: NSMutableAttributedString,
        paragraph: CoreHwp.HwpParagraph
    ) {
        guard output.length > 0 else { return }
        stripDecorationsFromEmptyLastLineAnchor(in: output)
        let paraShape = index.paraShapeOrDefault(for: paragraph)
        output.addAttribute(
            kCTParagraphStyleAttributeName as NSAttributedString.Key,
            value: HwpParagraphLayout.paragraphStyle(
                for: paraShape,
                attributedString: output,
                tabStops: attributeCache?.textTabs(for: paraShape, index: index)
                    ?? index.textTabs(for: paraShape)
            ),
            range: NSRange(location: 0, length: output.length)
        )
        attachTabLeaders(to: output, paraShape: paraShape)
        let alignment = paraShape.property1Info.alignmentRawValue
        if alignment == 4 || alignment == 5 {
            // 배분/나눔 정렬: 마지막 줄도 벌린다 (공공누리 실물 실측)
            output.addAttribute(
                HwpAttributedStringKey.distributeAlignment,
                value: NSNumber(value: true),
                range: NSRange(location: 0, length: output.length)
            )
        }
    }

    /// 탭 정의에 채움 (리더)이 있으면 탭 문자에 마커를 달아 렌더러가
    /// 탭 전진 구간에 점선을 그리게 한다 (legacy 목차 실물: '……' 리더)
    private func attachTabLeaders(
        to output: NSMutableAttributedString,
        paraShape: CoreHwp.HwpParaShape
    ) {
        guard let tabDef = index.tabDef(id: UInt32(paraShape.tabDefId)),
              tabDef.tabInfoArray.contains(where: { $0.fillType != 0 })
        else { return }
        // stop을 위치(pt)·채움으로 인코딩해 draw가 각 탭이 겨냥한 stop의 채움을
        // 위치로 판정하게 한다 (#4). 위치는 CTTextTab(index.textTabs)와 같은
        // 산식(HWPUNIT→pt, /2)이라 draw의 탭 run bounds와 정렬된다.
        let stops = tabDef.tabInfoArray
            .sorted { $0.location < $1.location }
            .flatMap { info -> [NSNumber] in
                let locPt = Double(HwpUnits.points(fromHwpUnitU: info.location) / 2)
                return [NSNumber(value: locPt), NSNumber(value: Int(info.fillType))]
            } as NSArray
        let text = output.string as NSString
        var location = 0
        while location < text.length {
            if text.character(at: location) == 0x09 {
                output.addAttribute(
                    HwpAttributedStringKey.tabLeader,
                    value: NSNumber(value: true),
                    range: NSRange(location: location, length: 1)
                )
                output.addAttribute(
                    HwpAttributedStringKey.tabLeaderStops,
                    value: stops,
                    range: NSRange(location: location, length: 1)
                )
            }
            location += 1
        }
    }
}

extension HwpTextRunBuilder {
    struct HyperlinkFrame {
        let depth: Int
        let start: Int
        let url: String
    }

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
        // 형식 문자(Cf)·결합 마크(M*)는 단독 스크립트가 없고 앞 글자와 한
        // 글리프로 결합하는 문자다 — 직전 스크립트를 상속해 같은 폰트 run에
        // 남겨야 CoreText가 이모지 ZWJ 시퀀스·아랍 결합열을 형성한다 (#4).
        let script: HwpScript = if let current = chunk.script, inheritsSurroundingScript(text) {
            current
        } else {
            detectScript(in: text)
        }
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
        let resolved = resolvedShape(id: chunk.shapeId, paragraph: paragraph)
        var chunkAttributes = attributes(for: resolved, script: script)
        applyTrackChangeMark(chunk.trackMark, to: &chunkAttributes)
        if chunk.memoAnchor,
           chunkAttributes[HwpAttributedStringKey.shadeColor] == nil
        {
            // 메모 앵커: 한글.app처럼 연녹색 배경 + 둥근 녹색 테두리 괄호
            chunkAttributes[HwpAttributedStringKey.shadeColor] =
                HwpMemoPanelPainter.anchorFillColor
            chunkAttributes[HwpAttributedStringKey.memoAnchorStroke] =
                HwpMemoPanelPainter.borderColor
        }
        let attributed = NSMutableAttributedString(
            string: chunk.text,
            attributes: chunkAttributes
        )
        // 워드 호환 문서 (표 20)와 '글꼴에 어울리는 빈칸'은 **보통 빈칸**만
        // 폰트 고유 폭으로 돌린다 — 제어 빈칸은 그 게이트 밖이다.
        Self.applyFixedSpaceWidth(
            to: attributed,
            includesOrdinarySpace: !resolved.shape.property.doesAdjustBlank
                && !index.isCompatibilityDocument
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
        let resolved = resolvedShape(id: shapeId, paragraph: paragraph)

        // 탭 (inline 코드 9)은 실제 탭으로 방출한다 (CT 탭 스톱 조판).
        if inlineValue == 9 {
            output.append(NSAttributedString(
                string: "\t",
                attributes: attributes(for: resolved, script: .english)
            ))
            return
        }

        // 치환 텍스트가 있으면 마커 대신 실제 번호 run을 방출한다.
        if let replacement, !replacement.text.isEmpty {
            let script = detectScript(in: replacement.text)
            var textAttributes = attributes(for: resolved, script: script)
            if replacement.isSuperscript {
                applySuperscript(to: &textAttributes, shape: resolved.shape)
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

        // 마커 전용 값 (controlIndex·inlineObjectHeight·run delegate)은 캐시된 사전의
        // 사본에만 붙는다 — 개체 크기가 controlIndex마다 다르므로 캐시에 넣으면 안 된다.
        var markerAttributes = attributes(for: resolved, script: .english)
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

    /// 캐시를 거친 `attributes(for:script:)`.
    ///
    /// `ResolvedShape`만 받으므로 캐시 키와 실제 shape가 어긋난 짝을 넘길 길이 없다
    /// (키에 shape 내용이 없어 어긋나면 조용히 오염된다).
    ///
    /// 돌려받은 사전은 **제자리에서 변형하지 말 것** (`HwpTextAttributeCache` 계약):
    /// 호출부는 `var` 사본에 키를 추가·치환만 한다.
    func attributes(
        for resolved: ResolvedShape,
        script: HwpScript
    ) -> [NSAttributedString.Key: Any] {
        guard let attributeCache else { return attributes(for: resolved.shape, script: script) }
        return attributeCache.attributes(shapeId: resolved.cacheKey, script: script) {
            attributes(for: resolved.shape, script: script)
        }
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
        let face = index.faceName(for: faceId, script: script)
        let faceName = face?.faceName ?? "Helvetica"
        var font = fontResolver.resolve(
            faceName: Self.serifLatinFallback(
                faceName,
                script: script,
                usesInstalledHancomFonts: fontResolver.usesInstalledHancomFonts
            ),
            alternatives: [face?.alternativeFaceName, face?.defaultFaceName].compactMap { $0 },
            script: script, size: size
        )
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
            HwpAttributedStringKey.baseFontSize: NSNumber(value: Double(baseSize)),
            HwpAttributedStringKey.spaceTargetSize: NSNumber(value: Double(size)),
            kCTForegroundColorAttributeName as NSAttributedString.Key: shape.faceColor.cgColor,
            kCTKernAttributeName as NSAttributedString.Key: NSNumber(
                value: Double(spacing * size / 100)
            ),
            kCTBaselineOffsetAttributeName as NSAttributedString.Key: NSNumber(
                value: Double(location * size / 100)
            ),
        ]
        if location != 0 {
            // CTFramesetter는 kCTBaselineOffset을 무시한다 — 렌더러가 직접
            // 시프트한다 (CharShape '글자위치' 실물: 양수 값이 아래로 내려감)
            attributes[HwpAttributedStringKey.glyphBaselineOffset] = NSNumber(
                value: Double(-location * size / 100)
            )
        }

        if shape.property.isBold,
           !CTFontGetSymbolicTraits(font).contains(.traitBold)
        {
            // 볼드 페이스 없는 폰트는 합성 볼드 (채움+윤곽)
            attributes[kCTStrokeWidthAttributeName as NSAttributedString.Key] =
                NSNumber(value: HwpRenderTuning.Text.syntheticBoldStrokeWidth)
        }
        applyShapeDecorations(to: &attributes, shape: shape, size: size)
        return attributes
    }

    /// 해석된 글자 모양과 그 캐시 키를 한 값으로 묶는다 — 짝이 어긋난 조합을
    /// `attributes(for:script:)`에 넘길 수 없게 하기 위해서다.
    ///
    /// `cacheKey`가 nil이면 `index`에 없는 id라 아래 폴백 상수를 쓴 것이다. 그런
    /// id는 결과 사전이 전부 같으므로 캐시에서 한 키로 접힌다.
    struct ResolvedShape {
        let shape: CoreHwp.HwpCharShape
        let cacheKey: UInt32?
    }

    func resolvedShape(id: UInt32, paragraph: CoreHwp.HwpParagraph) -> ResolvedShape {
        if let shape = index.charShape(id: id) {
            return ResolvedShape(shape: shape, cacheKey: id)
        }
        os_log(
            "HwpTextRunBuilder missing char shape: paraId=%{public}u shapeId=%{public}u",
            type: .default,
            paragraph.paraHeader.paraId,
            id
        )
        return ResolvedShape(shape: CoreHwp.HwpCharShape(), cacheKey: nil)
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

    /// 문맥 의존 문자만으로 이루어졌는가 — 형식 문자(Cf: ZWJ/ZWNJ/변이
    /// 선택자)와 결합 마크(Mn/Mc/Me)는 앞 글자에 붙어 렌더되므로 스크립트
    /// 판정 대신 직전 chunk의 스크립트를 상속받는다 (#4).
    func inheritsSurroundingScript(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .format, .nonspacingMark, .spacingMark, .enclosingMark:
                true
            default:
                false
            }
        }
    }

    /// 표시 상한까지 자르되 UTF-16 서로게이트 쌍을 쪼개지 않는다. 음수 상한은
    /// prefix 트랩을 막으려 0으로 클램프한다 (public API, R45 #3). 상한이 실제로
    /// 잘랐고 마지막이 lead 서로게이트면 짝(trail)이 잘려 나가 뒤에서 U+FFFD로
    /// 손상되므로 떨군다 (R46 #1). 자르지 않은 경우는 원본 그대로 (기존 동작 보존).
    func surrogateSafePrefix(
        _ units: [CoreHwp.HwpChar],
        upTo maxCharacters: Int
    ) -> ArraySlice<CoreHwp.HwpChar> {
        let clamped = Swift.max(0, maxCharacters)
        let prefix = units.prefix(clamped)
        if clamped < units.count, let last = prefix.last, last.type == .char,
           UTF16.isLeadSurrogate(last.value)
        {
            return prefix.dropLast()
        }
        return prefix
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
            if let text = Self.controlText(unit) {
                return text
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

    func value<T>(at index: Int, in array: [T], default fallback: T) -> T {
        array.indices.contains(index) ? array[index] : fallback
    }
}

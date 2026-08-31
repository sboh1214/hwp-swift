import Foundation

/// 섹션 XML 매핑이 들고 다니는 문맥 — id 테이블·BinData id 공간·옵션·엔트리
/// 이름과 재귀 깊이.
struct HwpxMappingContext {
    let idTables: HwpxIdTables
    let binItemIdByManifestId: [String: UInt16]
    let options: HwpLoadOptions
    let entry: String
    var depth = 0

    /// 미지 서브트리 합성에 쓰는 깊이 한도 — typed 재귀와 같은 설정을
    /// 따라야 호출자가 낮춘 한도가 진단 트리에도 선다 (파서의 512는 XML
    /// 요소 깊이 상한이지 호출자 한도가 아니다).
    var unknownDepthLimit: Int {
        options.readLimits.maxNestingDepth
    }

    /// typed 매퍼 재귀(표 셀 문단 등)의 유일한 깊이 가드 —
    /// `parseTreeRecord`의 level 가드와 같은 역할을 XML 쪽에서 한다.
    func descending() throws -> HwpxMappingContext {
        guard depth < options.readLimits.maxNestingDepth else {
            throw HwpError.invalidXML(
                entry: entry,
                reason: "element nesting exceeds maxNestingDepth "
                    + "\(options.readLimits.maxNestingDepth)"
            )
        }
        var next = self
        next.depth += 1
        return next
    }
}

/// `hp:p` 하나를 `HwpParagraph`로 옮긴다 — WCHAR 스트림 합성의 크럭스.
///
/// OWPML run 구조를 HWP5 제어 문자 스트림으로 재구성한다. 지켜야 하는
/// 불변식 (`HwpTextRunBuilder`·문단 검증이 의존):
/// - `paraCharShape.startingIndex`는 **원본 WCHAR 스트림 위치**다 — 텍스트
///   1 code unit = 1, inline/extended 제어 문자 = 8.
/// - extended 문자 추가와 `ctrlHeaderArray` 추가는 **동시**다 — run builder가
///   extended 서수로 배열을 직접 인덱싱한다. inline(필드 끝 4)은 슬롯이 없다.
/// - `paraHeader`의 count 4종은 같은 패스의 집계값이라 구성상 일치한다.
/// - 미지 요소는 앵커를 추측하지 않는다 — 위치가 불확실해지므로
///   `<hp:linesegarray>` 캐시를 폐기하고 CoreText reflow로 강등한다.
enum HwpxParagraphMapper {
    static func map(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext,
        isLastInList: Bool
    ) throws -> HwpParagraph {
        var builder = ParagraphBuilder(unknownDepthLimit: context.unknownDepthLimit)
        for child in node.childElements {
            if child.isNamed("run", in: HwpxNamespace.paragraph) {
                builder.beginRun(
                    shapeOffset: context.idTables.charShape.resolvedOffset(
                        of: child.attribute("charPrIDRef")
                    )
                )
                for runChild in child.childElements {
                    try consume(runChild, into: &builder, context: context)
                }
            } else if !child.isNamed("linesegarray", in: HwpxNamespace.paragraph) {
                // run/linesegarray가 아닌 hp:p 직속 자식(문단 직속 개체 등)은
                // synthetic unknown으로 남기고 위치 불확실로 표시한다 — 안 그러면
                // 진단에서 빠지고 positionCertain이 참으로 남아 안전밸브가 걸리지
                // 않은 채 잘못된 lineseg 캐시를 쓴다 (P2).
                builder.appendUnknown(child)
            }
        }
        builder.appendCharCode(13) // 문단 끝

        return try assemble(
            node, builder: builder, context: context, isLastInList: isLastInList
        )
    }
}

private extension HwpxParagraphMapper {
    static func consume(
        _ child: HwpxXMLNode,
        into builder: inout ParagraphBuilder,
        context: HwpxMappingContext
    ) throws {
        if child.isNamed("t", in: HwpxNamespace.paragraph) {
            consumeText(child, into: &builder)
            return
        }
        if child.isNamed("ctrl", in: HwpxNamespace.paragraph) {
            for wrapped in child.childElements {
                try classifyAndAppend(wrapped, into: &builder, context: context)
            }
            return
        }
        try classifyAndAppend(child, into: &builder, context: context)
    }

    static func classifyAndAppend(
        _ node: HwpxXMLNode,
        into builder: inout ParagraphBuilder,
        context: HwpxMappingContext
    ) throws {
        switch try HwpxControlMapper.classify(node, context: context) {
        case let .anchor(code, fourCC, ctrl):
            builder.appendAnchor(code: code, fourCC: fourCC, ctrl: ctrl)
        case let .inlineOnly(code, fourCC):
            builder.appendInline(code: code, fourCC: fourCC)
        case .zeroWidth:
            builder.recordZeroWidth(node.localName)
        case .unknown:
            builder.appendUnknown(node)
        }
    }

    /// `hp:t` — 텍스트와 인라인 요소(tab·lineBreak 등)의 원본 배치 순서가
    /// 곧 WCHAR 순서다 (`HwpxXMLNode.content`가 보존).
    static func consumeText(_ text: HwpxXMLNode, into builder: inout ParagraphBuilder) {
        for piece in text.content {
            switch piece {
            case let .text(string):
                for unit in string.utf16 {
                    builder.appendTextUnit(unit)
                }
            case let .element(element):
                consumeInlineTextChild(element, into: &builder)
            }
        }
    }

    static func consumeInlineTextChild(
        _ element: HwpxXMLNode,
        into builder: inout ParagraphBuilder
    ) {
        // classify와 같은 이유로 paragraph vocabulary 밖의 동명 요소를
        // 제어 문자로 오인하지 않는다 — 낯선 요소는 위치 불확실로 남긴다 (P2).
        guard element.namespaceURI.isEmpty
            || element.namespaceURI == HwpxNamespace.paragraph
        else {
            builder.appendUnknown(element)
            return
        }
        switch element.localName {
        case "tab":
            builder.appendInline(code: 9, fourCC: 0)
        case "lineBreak":
            builder.appendCharCode(10)
        case "hyphen":
            builder.appendCharCode(24)
        case "nbSpace":
            builder.appendCharCode(30)
        case "fwSpace":
            builder.appendCharCode(31)
        case "markpenBegin", "markpenEnd", "titleMark", "insertBegin", "insertEnd",
             "deleteBegin", "deleteEnd":
            // HWP5에서 WCHAR를 차지하지 않는 범위 표식(형광펜·변경 추적) —
            // 위치는 확실하므로 진단만 남긴다.
            builder.recordZeroWidth(element.localName)
        default:
            builder.appendUnknown(element)
            return
        }
        // 인식된 인라인 요소는 잎이다 — 하위를 삼키면 진단에서 빠지고
        // positionCertain이 참으로 남아 안전밸브가 걸리지 않은 채 잘못된
        // lineseg 캐시를 쓴다 (hp:p 직속 미지 자식과 같은 근거).
        for child in element.childElements {
            builder.appendUnknown(child)
        }
    }

    /// `<hp:linesegarray>` 안에서 채택되지 않는 요소 — 직계 비-lineseg 자식과
    /// lineseg의 자식(lineseg는 속성 전용이다).
    static func cacheUnknownRecords(
        in array: HwpxXMLNode, maxDepth: Int
    ) -> [HwpUnknownRecord] {
        array.childElements.flatMap { child -> [HwpUnknownRecord] in
            guard child.isNamed("lineseg", in: HwpxNamespace.paragraph) else {
                return [child.syntheticUnknownRecord(maxDepth: maxDepth)]
            }
            return child.childElements.map {
                $0.syntheticUnknownRecord(maxDepth: maxDepth)
            }
        }
    }

    static func assemble(
        _ node: HwpxXMLNode,
        builder: ParagraphBuilder,
        context: HwpxMappingContext,
        isLastInList: Bool
    ) throws -> HwpParagraph {
        var paragraph = HwpParagraph()
        paragraph.paraText = HwpParaText(rawPayload: Data(), charArray: builder.charArray)

        let (startingIndex, shapeId) = builder.charShapeArrays()
        var paraCharShape = HwpParaCharShape()
        paraCharShape.startingIndex = startingIndex
        paraCharShape.shapeId = shapeId
        paragraph.paraCharShape = paraCharShape

        let (lineSegs, lineSegUnknowns) = mapLineSegments(node, builder: builder)
        var paraLineSeg = HwpParaLineSeg()
        paraLineSeg.paraLineSegInternalArray = lineSegs
        paragraph.paraLineSeg = paraLineSeg

        // 헤더 count 필드는 UInt16이다 — count만 접고 배열을 남기면 "count ==
        // 배열 크기"라는 바이너리 로더 불변식이 깨진 모델이 나간다. XML 바이트
        // 한도 안에서 표현 가능한 입력이라 typed error로 거부한다 (복구
        // 모드에선 문단 placeholder로 흡수 — #65).
        guard startingIndex.count <= Int(UInt16.max),
              lineSegs.count <= Int(UInt16.max)
        else {
            throw HwpError.invalidXML(
                entry: context.entry,
                reason: "paragraph char-shape or line-segment entries exceed \(UInt16.max)"
            )
        }

        paragraph.ctrlHeaderArray = builder.ctrls
        paragraph.paraRangeTagArray = []
        paragraph.listHeaderArray = []
        paragraph.unknownChildren = builder.unknownChildren + lineSegUnknowns
        paragraph.paraHeader = HwpParaHeader(
            hwpxCharCount: builder.wcharPosition,
            controlMask: builder.controlMask,
            paraShapeId: UInt16(clamping: context.idTables.paraShape.resolvedOffset(
                of: node.attribute("paraPrIDRef")
            )),
            paraStyleId: UInt8(clamping: context.idTables.style.resolvedOffset(
                of: node.attribute("styleIDRef")
            )),
            columnType: columnType(of: node),
            charShapeInfoCount: UInt16(clamping: startingIndex.count),
            alignInfoCount: UInt16(clamping: lineSegs.count),
            paraId: node.uint32Attribute("id", default: 0),
            isLastInList: isLastInList
        )
        return paragraph
    }

    /// 쪽/단 나누기 — paginator는 bit 2(쪽 나누기)만 읽는다.
    static func columnType(of node: HwpxXMLNode) -> UInt8 {
        var value: UInt8 = 0
        if node.boolAttribute("pageBreak") {
            value |= 0b100
        }
        if node.boolAttribute("columnBreak") {
            value |= 0b1000
        }
        return value
    }

    /// `<hp:linesegarray>` → 절대 캐시 조판 입력. 9개 속성이
    /// `HwpParaLineSegInternal`과 1:1이다 (번들 템플릿 실측).
    ///
    /// **안전밸브**: 위치가 불확실하거나(미지 요소) 캐시가 sanity를 어기면
    /// (첫 textpos ≠ 0·비단조·범위 초과) 빈 배열로 강등한다 — 문단은 lineseg
    /// 부재를 허용하고 조판은 CoreText reflow로 넘어간다. 잘못된 캐시로
    /// 줄을 엉뚱한 위치에서 자르는 것보다 낫다.
    static func mapLineSegments(
        _ node: HwpxXMLNode,
        builder: ParagraphBuilder
    ) -> (segments: [HwpParaLineSegInternal], unknowns: [HwpUnknownRecord]) {
        guard let array = node.firstChild(named: "linesegarray") else {
            return ([], [])
        }
        // 캐시를 어떤 이유로 버리든 그 안 미지 요소는 진단에 남긴다 — 바깥
        // 문단 루프가 linesegarray를 건너뛰므로 이 지점이 그 자식을 걷는
        // 유일한 곳이다 (위치가 이미 불확실한 문단도 마찬가지다).
        let unknowns = cacheUnknownRecords(in: array, maxDepth: builder.unknownDepthLimit)
        guard builder.positionCertain else {
            return ([], unknowns)
        }
        // 미지 자식이 섞인 캐시는 통째로 거부한다 — lineseg만 골라 채택하면
        // 위치가 불확실한 캐시가 절대 조판의 신뢰 입력이 된다 (안전밸브의
        // "미지 요소" 축).
        let segmentNodes = array.paragraphChildren(named: "lineseg")
        guard segmentNodes.count == array.childElements.count,
              // lineseg는 속성 전용이다 — 자식을 가진 세그먼트는 그 자체로
              // 불확실한 캐시 메타데이터다 (직계 수 대조만으로는 세그먼트 안
              // 미지 요소가 통과한다).
              segmentNodes.allSatisfy(\.childElements.isEmpty)
        else {
            return ([], unknowns)
        }
        // textpos는 다른 8속성과 달리 **sanity 판정의 기준**이라 기본값을
        // 줄 수 없다 — 누락·비숫자를 0으로 합성하면 가장 불확실한 캐시가
        // "첫 textpos 0" 가드를 통과해 절대 조판의 신뢰 입력이 된다.
        // textpos만이 아니라 9속성 전부가 판정 기준이다 — 누락·비숫자를 0으로
        // 합성하면 높이 0 줄 같은 손상 기하가 절대 조판에 채택된다. 값 0은
        // 합법이므로 (첫 줄 vertpos·horzpos 등) 거부 대상은 부재·비숫자다.
        let requiredInt32Attributes = [
            "vertpos", "vertsize", "textheight", "baseline",
            "spacing", "horzpos", "horzsize",
        ]
        guard segmentNodes.allSatisfy({ segment in
            segment.attribute("textpos").flatMap(UInt32.init) != nil
                && segment.attribute("flags").flatMap(UInt32.init) != nil
                && requiredInt32Attributes.allSatisfy {
                    segment.attribute($0).flatMap(Int32.init) != nil
                }
        })
        else {
            return ([], [])
        }
        let segments = segmentNodes.map {
            HwpParaLineSegInternal(
                textStartingIndex: $0.uint32Attribute("textpos", default: 0),
                lineLocation: $0.int32Attribute("vertpos", default: 0),
                lineHeight: $0.int32Attribute("vertsize", default: 0),
                textHeight: $0.int32Attribute("textheight", default: 0),
                baselineDistance: $0.int32Attribute("baseline", default: 0),
                lineSpacing: $0.int32Attribute("spacing", default: 0),
                startingLocation: $0.int32Attribute("horzpos", default: 0),
                width: $0.int32Attribute("horzsize", default: 0),
                property: $0.uint32Attribute("flags", default: 0)
            )
        }
        guard let first = segments.first, first.textStartingIndex == 0 else {
            return ([], [])
        }
        var previous: UInt32 = 0
        for segment in segments {
            guard segment.textStartingIndex >= previous,
                  segment.textStartingIndex < max(1, builder.wcharPosition)
            else {
                return ([], [])
            }
            previous = segment.textStartingIndex
        }
        return (segments, [])
    }
}

/// 단일 패스 WCHAR 스트림 빌더.
private struct ParagraphBuilder {
    let unknownDepthLimit: Int
    private(set) var charArray: [HwpChar] = []
    private(set) var ctrls: [HwpCtrlId] = []
    private(set) var wcharPosition: UInt32 = 0
    private(set) var controlMask: UInt32 = 0
    private(set) var positionCertain = true
    private(set) var unknownChildren: [HwpUnknownRecord] = []
    private var shapeEntries: [(start: UInt32, shape: UInt32)] = []

    mutating func beginRun(shapeOffset: UInt32) {
        shapeEntries.append((wcharPosition, shapeOffset))
    }

    mutating func appendTextUnit(_ unit: UInt16) {
        charArray.append(HwpChar(type: .char, value: unit))
        wcharPosition += 1
    }

    /// 제어 코드지만 payload 없는 char 취급 코드 (10·13·24·30·31 — HWP5
    /// 파서의 default 분기와 동일하게 1 WCHAR).
    mutating func appendCharCode(_ code: UInt16) {
        charArray.append(HwpChar(type: .char, value: code))
        wcharPosition += 1
    }

    mutating func appendInline(code: UInt16, fourCC: UInt32) {
        charArray.append(HwpChar(
            type: .inline, value: code, payload: Self.controlPayload(code: code, fourCC: fourCC)
        ))
        wcharPosition += 8
        controlMask |= 1 << UInt32(min(code, 31))
    }

    mutating func appendAnchor(code: UInt16, fourCC: UInt32, ctrl: HwpCtrlId) {
        charArray.append(HwpChar(
            type: .extended, value: code,
            payload: Self.controlPayload(code: code, fourCC: fourCC)
        ))
        ctrls.append(ctrl)
        wcharPosition += 8
        controlMask |= 1 << UInt32(min(code, 31))
    }

    mutating func appendUnknown(_ element: HwpxXMLNode) {
        positionCertain = false
        unknownChildren.append(element.syntheticUnknownRecord(maxDepth: unknownDepthLimit))
    }

    mutating func recordZeroWidth(_ elementName: String) {
        unknownChildren.append(HwpUnknownRecord(
            tagId: hwpxSyntheticTagId, level: 0, payload: Data(elementName.utf8)
        ))
    }

    /// run 경계를 글자 모양 **변경점**으로 접는다 — HWP5의
    /// PARA_CHAR_SHAPE는 모양이 바뀌는 위치만 기록한다. 시작 위치가 같은
    /// 항목은 마지막이 이기고(빈 run이 다음 run과 같은 위치에 겹칠 때),
    /// 직전과 모양이 같은 경계는 기록하지 않는다. 항목이 없으면 HWP5 최소
    /// 계약([0]/[0])으로 채운다.
    func charShapeArrays() -> (startingIndex: [UInt32], shapeId: [UInt32]) {
        var startingIndex: [UInt32] = []
        var shapeId: [UInt32] = []
        for entry in shapeEntries {
            if startingIndex.last == entry.start {
                shapeId[shapeId.count - 1] = entry.shape
                if shapeId.count >= 2, shapeId[shapeId.count - 2] == entry.shape {
                    startingIndex.removeLast()
                    shapeId.removeLast()
                }
            } else if shapeId.last != entry.shape {
                startingIndex.append(entry.start)
                shapeId.append(entry.shape)
            }
        }
        if startingIndex.isEmpty {
            return ([0], [0])
        }
        return (startingIndex, shapeId)
    }

    /// 14바이트 합성 payload — 선두 4바이트 LE ctrl id
    /// (`HwpInlineControl.rawControlId`가 읽는 자리) + 예약 8바이트 +
    /// 후미 2바이트 코드 반복 (HWP5 스트림 관행).
    static func controlPayload(code: UInt16, fourCC: UInt32) -> Data {
        var payload = Data(capacity: 14)
        payload.append(UInt8(fourCC & 0xFF))
        payload.append(UInt8((fourCC >> 8) & 0xFF))
        payload.append(UInt8((fourCC >> 16) & 0xFF))
        payload.append(UInt8((fourCC >> 24) & 0xFF))
        payload.append(contentsOf: [UInt8](repeating: 0, count: 8))
        payload.append(UInt8(code & 0xFF))
        payload.append(UInt8(code >> 8))
        return payload
    }
}

extension HwpParaLineSegInternal {
    /// HWPX `<hp:lineseg>` 9개 속성 1:1 대응 init.
    init(
        textStartingIndex: UInt32,
        lineLocation: Int32,
        lineHeight: Int32,
        textHeight: Int32,
        baselineDistance: Int32,
        lineSpacing: Int32,
        startingLocation: Int32,
        width: Int32,
        property: UInt32
    ) {
        self.textStartingIndex = textStartingIndex
        self.lineLocation = lineLocation
        self.lineHeight = lineHeight
        self.textHeight = textHeight
        self.baselineDistance = baselineDistance
        self.lineSpacing = lineSpacing
        self.startingLocation = startingLocation
        self.width = width
        self.property = property
    }
}

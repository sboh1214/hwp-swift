import Foundation

/// `hh:fontfaces`·`hh:charPr`를 `HwpFaceName`·`HwpCharShape`로 옮긴다.
///
/// OWPML 글자 모양은 KS X 6101의 이름 붙은 값이고 HWP5는 bit field지만,
/// 두 포맷의 수치 단위는 같다 (baseSize = 1/100pt, 장평/자간/상대크기 = %).
/// 렌더 스택은 `HwpCharShapeProperty`의 typed 필드만 읽으므로 `rawValue`
/// bit 재합성은 하지 않는다.
enum HwpxCharShapeMapper {
    /// `hh:fontface lang="…"` 목록 → 7개 faceName 배열 + 언어별 id 테이블.
    /// 1차 등록 패스용 — `mapFontFaces`와 같은 순회로 언어별 폰트 id만
    /// 등록한다. fontfaces가 charProperties 뒤에 오는 문서에서도 fontRef가
    /// 해석되게 하는 순서 독립 등록이다 (다른 7가족과 같은 규약).
    static func registerFontFaces(_ fontfaces: HwpxXMLNode, into tables: inout HwpxIdTables) {
        var counts = [Int](repeating: 0, count: 7)
        for fontface in fontfaces.headChildren(named: "fontface") {
            guard let language = fontface.attribute("lang")
                .flatMap(HwpxFontLanguage.init(rawValue:))
            else {
                continue
            }
            let index = language.arrayIndex
            for font in fontface.headChildren(named: "font") {
                tables.fontFacesByLanguage[index].register(
                    id: font.attribute("id"), offset: counts[index]
                )
                counts[index] += 1
            }
        }
    }

    static func mapFontFaces(
        _ fontfaces: HwpxXMLNode,
        into idMappings: inout HwpIdMappings,
        tables: inout HwpxIdTables,
        unknownRecords: inout [HwpUnknownRecord]
    ) throws {
        var arrays: [[HwpFaceName]] = Array(repeating: [], count: 7)
        for fontface in fontfaces.headChildren(named: "fontface") {
            guard let language = fontface.attribute("lang")
                .flatMap(HwpxFontLanguage.init(rawValue:))
            else {
                // 미지 lang의 fontface는 글꼴 목록이 통째로 빠지므로 조용히
                // 버리면 안 된다 — 진단으로 남긴다.
                unknownRecords.append(fontface.syntheticUnknownRecord())
                continue
            }
            let index = language.arrayIndex
            unknownRecords += fontface.headDecoyRecords(named: "font")
            for font in fontface.headChildren(named: "font") {
                let face = font.attribute("face") ?? ""
                let substitute = font.firstChild(named: "substFont")?.attribute("face")
                try hwpxValidateNameLength(face)
                if let substitute {
                    try hwpxValidateNameLength(substitute)
                }
                // typeInfo 등 1차 범위 밖 자식은 진단으로 강등한다.
                unknownRecords += font.unconsumedChildRecords(consumed: ["substFont"])
                tables.fontFacesByLanguage[index].register(
                    id: font.attribute("id"), offset: arrays[index].count
                )
                arrays[index].append(HwpFaceName(
                    hwpxFace: face, substituteFace: substitute
                ))
            }
        }
        idMappings.faceNameKoreanArray = arrays[0]
        idMappings.faceNameEnglishArray = arrays[1]
        idMappings.faceNameChineseArray = arrays[2]
        idMappings.faceNameJapaneseArray = arrays[3]
        idMappings.faceNameEtcArray = arrays[4]
        idMappings.faceNameSymbolArray = arrays[5]
        idMappings.faceNameUserArray = arrays[6]
    }

    /// `hh:charPr` 하나 → `HwpCharShape`.
    static func mapCharShape(_ node: HwpxXMLNode, tables: HwpxIdTables) -> HwpCharShape {
        let fontRef = node.firstChild(named: "fontRef")
        let ratio = node.firstChild(named: "ratio")
        let spacing = node.firstChild(named: "spacing")
        let relativeSize = node.firstChild(named: "relSz")
        let offset = node.firstChild(named: "offset")

        var property = HwpCharShapeProperty()
        property.isBold = node.firstChild(named: "bold") != nil
        property.isItalic = node.firstChild(named: "italic") != nil
        property.isRelief = node.firstChild(named: "emboss") != nil
        property.isCounterRelief = node.firstChild(named: "engrave") != nil
        property.isSuperscript = node.firstChild(named: "supscript") != nil
        property.isSubscript = node.firstChild(named: "subscript") != nil
        property.isKerning = node.boolAttribute("useKerning")
        property.doesAdjustBlank = node.boolAttribute("useFontSpace")
        property.emphasisType = Self.emphasisTypes[node.attribute("symMark") ?? "NONE"]
            ?? .none

        let underline = node.firstChild(named: "underline")
        var underlineColor = HwpColor()
        if let underline {
            property.underlineType = Self.underlineTypes[
                underline.attribute("type") ?? "NONE"
            ] ?? HwpUnderlineType.none
            property.underlineShape = Self.lineShapeIndex(
                underline.attribute("shape"), default: 1
            )
            underlineColor = underline.colorAttribute("color") ?? HwpColor()
        }

        let strikeout = node.firstChild(named: "strikeout")
        var strikethroughColor: HwpColor? = HwpColor()
        if let strikeout {
            let shape = strikeout.attribute("shape") ?? "NONE"
            if shape != "NONE" {
                property.strikethrough = 1
                property.strikethroughShape = Self.lineShapeIndex(shape, default: 1)
            }
            strikethroughColor = strikeout.colorAttribute("color") ?? HwpColor()
        }

        if let outline = node.firstChild(named: "outline") {
            property.borderlineType = Self.outlineTypes[
                outline.attribute("type") ?? "NONE"
            ] ?? HwpBorderLineType.none
        }

        let shadow = node.firstChild(named: "shadow")
        var shadowType = HwpShadowType.none
        if let shadow {
            shadowType = Self.shadowTypes[shadow.attribute("type") ?? "NONE"]
                ?? HwpShadowType.none
        }
        property.shadowType = shadowType

        return HwpCharShape(
            hwpxFaceId: Self.perLanguageWords(fontRef) { language, ref in
                WORD(clamping: tables.fontFacesByLanguage[language.arrayIndex]
                    .resolvedOffset(of: ref))
            },
            faceScaleX: Self.perLanguageValues(ratio, default: 100) { UInt8(clamping: $0) },
            faceSpacing: Self.perLanguageValues(spacing, default: 0) { Int8(clamping: $0) },
            faceRelativeSize: Self.perLanguageValues(relativeSize, default: 100) {
                UInt8(clamping: $0)
            },
            faceLocation: Self.perLanguageValues(offset, default: 0) { Int8(clamping: $0) },
            baseSize: node.int32Attribute("height", default: 1000),
            property: property,
            shadowIntervalX: Int8(clamping: shadow?.intAttribute("offsetX", default: 10) ?? 10),
            shadowIntervalY: Int8(clamping: shadow?.intAttribute("offsetY", default: 10) ?? 10),
            faceColor: node.colorAttribute("textColor") ?? HwpColor(),
            underlineColor: underlineColor,
            shadeColor: node.colorAttribute("shadeColor") ?? HwpColor(255, 255, 255),
            shadowColor: shadow?.colorAttribute("color") ?? HwpColor(192, 192, 192),
            borderFillId: tables.borderFillId(of: node.attribute("borderFillIDRef")),
            strikethroughColor: strikethroughColor
        )
    }
}

extension HwpxCharShapeMapper {
    /// OWPML 언어 속성 이름 — `HwpxFontLanguage.arrayIndex` 순서.
    static let languageAttributes = [
        "hangul", "latin", "hanja", "japanese", "other", "symbol", "user",
    ]

    static func perLanguageValues<T>(
        _ node: HwpxXMLNode?,
        default defaultValue: Int,
        _ convert: (Int) -> T
    ) -> [T] {
        languageAttributes.map { attribute in
            convert(node?.intAttribute(attribute, default: defaultValue) ?? defaultValue)
        }
    }

    static func perLanguageWords(
        _ node: HwpxXMLNode?,
        _ resolve: (HwpxFontLanguage, String?) -> WORD
    ) -> [WORD] {
        HwpxFontLanguage.allCases.map { language in
            resolve(language, node?.attribute(Self.languageAttributes[language.arrayIndex]))
        }
    }

    /// OWPML 선 모양 이름 → HWP5 표 27 계열 index (밑줄·취소선·외곽선 공용).
    static let lineShapes: [String: Int] = [
        "NONE": 0, "SOLID": 1, "DASH": 2, "DOT": 3, "DASH_DOT": 4,
        "DASH_DOT_DOT": 5, "LONG_DASH": 6, "CIRCLE": 7, "DOUBLE_SLIM": 8,
        "SLIM_THICK": 9, "THICK_SLIM": 10, "SLIM_THICK_SLIM": 11,
        "WAVE": 12, "DOUBLEWAVE": 13, "THICK_3D": 14,
        "THICK_3D_REVERSE_LIGHTING": 15, "SOLID_3D": 16,
        "SOLID_3D_REVERSE_LIGHTING": 17,
    ]

    static func lineShapeIndex(_ name: String?, default defaultValue: Int) -> Int {
        guard let name else {
            return defaultValue
        }
        return lineShapes[name] ?? defaultValue
    }

    /// OWPML LineType1 → 표 33 글자 외곽선. 밑줄·취소선의 `lineShapes`(표 27
    /// 계열)와 인덱스 체계가 다르다 — 공유하면 DOT/DASH가 다른 의미로 매핑되고
    /// THICK이 표에 없어 굵은 외곽선이 .none으로 사라진다.
    static let outlineTypes: [String: HwpBorderLineType] = [
        "NONE": .none, "SOLID": .line, "DOT": .dot, "THICK": .thickLine,
        "DASH": .loneDot, "DASH_DOT": .oneDotOneLine,
        "DASH_DOT_DOT": .twoDotsOneLine,
    ]

    static let underlineTypes: [String: HwpUnderlineType] = [
        "NONE": .none, "BOTTOM": .under, "TOP": .above,
    ]

    static let shadowTypes: [String: HwpShadowType] = [
        "NONE": .none, "DROP": .discontinuous, "CONTINUOUS": .continuous,
    ]

    static let emphasisTypes: [String: HwpEmphasisType] = [
        "NONE": .none, "DOT_ABOVE": .filledCircle, "RING_ABOVE": .outlinedCircle,
        "CHECK": .caron, "TILDE": .tilde, "MIDDLE_DOT": .interpunct, "COLON": .colon,
    ]
}

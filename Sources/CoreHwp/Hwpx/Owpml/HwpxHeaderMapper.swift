import Foundation

/// XML에서 온 요소를 진단에 실을 때 쓰는 합성 tag id.
///
/// 실제 HWP5 태그 공간(0x10 이상)과 겹치지 않는 0을 세워 두고, 요소 이름을
/// UTF-8로 payload에 싣는다 — `parseDiagnostics()`의 `unknownRecord` 경로가
/// 무변경으로 HWPX 미해석 요소를 보고하게 하는 규약이다 (tagId 0 + payload =
/// OWPML local name).
let hwpxSyntheticTagId: UInt32 = 0

/// 글꼴·스타일 이름을 WORD 길이 필드로 축소하기 전에 검증한다.
///
/// `HwpFaceName`/`HwpStyle`의 합성 init은 `WORD(name.utf16.count)`로 이름
/// 길이를 담는데, 65,536 UTF-16 단위 이상이면 그 축소가 트랩한다. 기본 엔트리
/// 한도로 그만한 이름이 통과하므로, 프로세스 중단 대신 typed `invalidXML`로
/// 거부한다 (P1). 이름은 전부 header.xml에서 온다.
func hwpxValidateNameLength(_ name: String, entry: String) throws {
    guard name.utf16.count <= Int(WORD.max) else {
        throw HwpError.invalidXML(
            entry: entry,
            reason: "font or style name exceeds \(WORD.max) UTF-16 units"
        )
    }
}

/// `Contents/header.xml`(`hh:head`) 전체를 `HwpDocInfo` 구성 요소로 옮긴다.
struct HwpxHeaderMapping {
    var documentProperties = HwpDocumentProperties()
    var idMappings = HwpIdMappings()
    var idTables = HwpxIdTables()
    var unknownRecords: [HwpUnknownRecord] = []
    /// 미지 서브트리 합성의 깊이 한도 — 호출자의 `maxNestingDepth`다.
    var unknownDepthLimit = HwpReadLimits.default.maxNestingDepth
    /// 이 헤더가 실제로 읽힌 엔트리 이름 — manifest가 관례 아닌 href를
    /// 선언할 수 있으므로 진단은 이것을 가리켜야 한다 (패키지 문서와 같다).
    var entry = HwpxContainer.EntryName.header

    /// 강등은 전부 이 셋을 지난다 — 호출부마다 한도를 다는 방식이면 새
    /// 경로가 그것을 빠뜨린다 (본문 경로만 전파하고 헤더를 빠뜨린 것이
    /// 이 규약의 첫 결함이었다).
    mutating func demote(_ node: HwpxXMLNode) {
        unknownRecords.append(node.syntheticUnknownRecord(maxDepth: unknownDepthLimit))
    }

    mutating func demoteUnconsumed(in node: HwpxXMLNode, consumed: Set<String>) {
        unknownRecords += node.unconsumedChildRecords(
            consumed: consumed, maxDepth: unknownDepthLimit
        )
    }

    mutating func demoteUnconsumed(
        in node: HwpxXMLNode, consumed: Set<String>, namespace: String
    ) {
        unknownRecords += node.unconsumedChildRecords(
            consumed: consumed, in: namespace, maxDepth: unknownDepthLimit
        )
    }

    mutating func demoteUnconsumed(in node: HwpxXMLNode, consumed: [String: String]) {
        unknownRecords += node.unconsumedChildRecords(
            consumed: consumed, maxDepth: unknownDepthLimit
        )
    }

    /// 단일 조회로 읽는 이름의 두 번째 이후 등장을 진단으로 강등한다 —
    /// 소비 표시는 이름 단위라 중복도 소비로 접힌다 (`duplicateSingletonRecords`).
    mutating func demoteDuplicateSingletons(
        in node: HwpxXMLNode, of names: [String], namespace: String
    ) {
        unknownRecords += node.duplicateSingletonRecords(
            of: names, in: namespace, maxDepth: unknownDepthLimit
        )
    }

    mutating func demoteDuplicateSingletons(
        in node: HwpxXMLNode, of namespaces: [String: String]
    ) {
        unknownRecords += node.duplicateSingletonRecords(
            of: namespaces, maxDepth: unknownDepthLimit
        )
    }
}

enum HwpxHeaderMapper {
    static func map(
        _ data: Data,
        binDataCatalog: HwpxBinDataCatalog,
        options: HwpLoadOptions,
        sectionCount: Int? = nil,
        entry: String
    ) throws -> (docInfo: HwpDocInfo, idTables: HwpxIdTables) {
        let root = try HwpxXMLTreeParser.parse(data, entry: entry)
        guard root.isNamed("head", in: HwpxNamespace.head) else {
            throw HwpError.invalidXML(
                entry: entry,
                reason: "unexpected root element <\(root.localName)>"
            )
        }

        var mapping = HwpxHeaderMapping()
        mapping.unknownDepthLimit = options.readLimits.maxNestingDepth
        mapping.entry = entry
        // 실재 구역 수(조립기가 셈)가 secCnt 선언보다 정확하다 — 선언이
        // 어긋난 문서에서 모델 내부 일관성을 지킨다.
        let sections = sectionCount ?? root.intAttribute("secCnt", default: 1)
        // sectionSize는 UInt16인데 조립기는 spine 목록 전체로 구역을 만든다
        // (중복 itemref도 각각) — 클램프하면 sectionArray.count == sectionSize
        // 불변식이 깨진 모델이 나가므로 거부한다. 중복 제거는 처방이 아니다:
        // 중복 참조를 몇 구역으로 조립할지는 별개 정책이라 렌더가 달라진다.
        guard sections <= Int(UInt16.max) else {
            throw HwpError.invalidXML(
                entry: entry,
                reason: "section count exceeds the 65,535-entry model field"
            )
        }
        mapping.documentProperties.sectionSize = UInt16(clamping: sections)

        // 빈 문서 기본값에서 출발하되, 매핑 대상 가족은 전부 덮어쓴다 —
        // 기본값 항목이 리맵된 오프셋 공간에 섞이면 참조가 어긋난다.
        mapping.idMappings.binDataArray = binDataCatalog.binDataArray
        // 7개 언어별 글꼴 배열을 전부 비운다 — HwpIdMappings()가 일곱 배열 모두를
        // 기본 2종으로 채우므로, fontfaces 가족이 없는 헤더에서 한국어만 비우면
        // 나머지 6종이 패키지에 없는 글꼴을 광고한다 (P2).
        mapping.idMappings.faceNameKoreanArray = []
        mapping.idMappings.faceNameEnglishArray = []
        mapping.idMappings.faceNameChineseArray = []
        mapping.idMappings.faceNameJapaneseArray = []
        mapping.idMappings.faceNameEtcArray = []
        mapping.idMappings.faceNameSymbolArray = []
        mapping.idMappings.faceNameUserArray = []
        mapping.idMappings.borderFillArray = []
        mapping.idMappings.charShapeArray = []
        mapping.idMappings.tabDefArray = []
        mapping.idMappings.numberingArray = []
        mapping.idMappings.bulletArray = []
        mapping.idMappings.paraShapeArray = []
        mapping.idMappings.styleArray = []
        mapping.idMappings.forbiddenCharArray = []
        mapping.idMappings.memoShapeCount = nil
        mapping.idMappings.changeTraceCount = nil
        mapping.idMappings.changeTraceUserCount = nil

        try mapHeadChildren(root, into: &mapping)

        let docInfo = HwpDocInfo(
            hwpxDocumentProperties: mapping.documentProperties,
            idMappings: mapping.idMappings,
            unknownRecords: mapping.unknownRecords,
            rawPayload: options.preservedPayload(data)
        )
        return (docInfo, mapping.idTables)
    }
}

private extension HwpxHeaderMapper {
    static func mapHeadChildren(
        _ root: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        // head 직계 자식은 head vocabulary 하나로 정해지는 자리다 — 전역
        // known 매칭이면 <hp:beginNum> 같은 타 vocabulary 디코이가 시작
        // 번호를 조용히 덮는다 (가족 루프의 head 좁히기와 같은 근거).
        // beginNum·refList는 head 아래 한 번씩 오는 자리다 — 두 번째부터도
        // 적용하면 마지막이 이겨 ("첫 등장이 이긴다"와 반대) 앞선 선언이
        // 조용히 덮이고 진단에도 안 남는다.
        var applied = Set<String>()
        for child in root.childElements {
            if child.isNamed("beginNum", in: HwpxNamespace.head) {
                guard applied.insert("beginNum").inserted else {
                    mapping.demote(child)
                    continue
                }
                mapping.documentProperties = HwpDocumentProperties(
                    hwpxSectionSize: mapping.documentProperties.sectionSize,
                    startingIndex: HwpStartingIndex(
                        hwpxPage: child.uint16Attribute("page", default: 1),
                        footnote: child.uint16Attribute("footnote", default: 1),
                        endnote: child.uint16Attribute("endnote", default: 1),
                        picture: child.uint16Attribute("pic", default: 1),
                        table: child.uint16Attribute("tbl", default: 1),
                        equation: child.uint16Attribute("equation", default: 1)
                    )
                )
                mapping.demoteUnconsumed(in: child, consumed: [])
            } else if child.isNamed("refList", in: HwpxNamespace.head) {
                guard applied.insert("refList").inserted else {
                    mapping.demote(child)
                    continue
                }
                try mapRefList(child, into: &mapping)
            } else {
                mapping.demote(child)
            }
        }
    }

    static func mapRefList(
        _ refList: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        registerFamilies(refList, into: &mapping)
        try mapFamilies(refList, into: &mapping)
    }

    /// 1차 패스: 가족별 id 테이블 등록 — 가족 사이 참조(글자→테두리,
    /// 스타일→문단/글자, 문단→탭/번호)가 문서 내 등장 순서와 무관하게
    /// 해석되도록 등록을 먼저 끝낸다.
    static func registerFamilies(
        _ refList: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) {
        // 가족은 refList 안에 한 번씩 온다 — 중복 가족까지 등록하면 offset이
        // 가족마다 0부터 다시 매겨져 두 가족의 서로 다른 id가 같은 슬롯을
        // 신청한다. 첫 가족만 등록해 오프셋 공간을 하나로 유지한다 (2차
        // 패스의 강등과 짝이다).
        var registered = Set<String>()
        for family in refList.childElements
            where family.isNamed(family.localName, in: HwpxNamespace.head)
        {
            guard registered.insert(family.localName).inserted else {
                continue
            }
            switch family.localName {
            case "fontfaces":
                HwpxCharShapeMapper.registerFontFaces(family, into: &mapping.idTables)
            case "borderFills":
                register(family, "borderFill", into: &mapping.idTables.borderFill)
            case "charProperties":
                register(family, "charPr", into: &mapping.idTables.charShape)
            case "tabProperties":
                register(family, "tabPr", into: &mapping.idTables.tabDef)
            case "numberings":
                register(family, "numbering", into: &mapping.idTables.numbering)
            case "bullets":
                register(family, "bullet", into: &mapping.idTables.bullet)
            case "paraProperties":
                register(family, "paraPr", into: &mapping.idTables.paraShape)
            case "styles":
                register(family, "style", into: &mapping.idTables.style)
            default:
                break
            }
        }
    }

    /// 2차 패스: 모델 매핑. 가족은 head vocabulary여야 한다 — 전역 known
    /// 매칭이면 hp:styles 같은 동명 가족이 hh 정의로 매핑돼 id 테이블을
    /// 다시 쓴다 ((namespace, local name) 규칙).
    static func mapFamilies(
        _ refList: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        var mapped = Set<String>()
        for family in refList.childElements {
            guard family.isNamed(family.localName, in: HwpxNamespace.head) else {
                mapping.demote(family)
                continue
            }
            // 같은 가족이 두 번 오면 배열은 대입이라 **마지막**이 이기는데 id
            // 테이블은 **첫 등장**이 이겨, 첫 가족의 id가 두 번째 가족의
            // 정의로 해석된다 (조용한 서식 오염 — 진단에도 안 남는다).
            // 첫 등장만 소비하고 나머지는 가족째 진단에 남긴다 (바이너리
            // ID_MAPPINGS의 singleton 슬롯 계약과 같다). `continue`가 필수다 —
            // 아래 가족 자식 강등까지 흐르면 같은 자식이 두 번 실린다.
            guard mapped.insert(family.localName).inserted else {
                mapping.demote(family)
                continue
            }
            switch family.localName {
            case "fontfaces":
                let depthLimit = mapping.unknownDepthLimit
                try HwpxCharShapeMapper.mapFontFaces(
                    family,
                    into: &mapping.idMappings,
                    tables: &mapping.idTables,
                    unknownRecords: &mapping.unknownRecords,
                    maxDepth: depthLimit,
                    entry: mapping.entry
                )
            case "borderFills":
                try mapBorderFills(family, into: &mapping)
            case "charProperties":
                try mapCharProperties(family, into: &mapping)
            case "tabProperties":
                try mapTabProperties(family, into: &mapping)
            case "paraProperties":
                try mapParaProperties(family, into: &mapping)
            case "styles":
                try mapStyles(family, into: &mapping)
            case "numberings":
                try mapNumberings(family, into: &mapping)
            case "bullets":
                try mapBullets(family, into: &mapping)
            default:
                mapping.demote(family)
            }
            demoteUnconsumedFamilyChildren(in: family, into: &mapping)
        }
    }

    /// `hh:styles` 가족을 스타일 배열로 옮긴다.
    ///
    /// 스타일 참조(문단 paraStyleId·스타일 nextId)는 UInt8이다 — 257번째부터
    /// 등장 순서 오프셋이 255로 별칭화되어 리맵 단사성이 깨지므로 정의 수를
    /// 참조 공간(256)으로 제한한다.
    static func mapStyles(
        _ family: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        let styles = family.headChildren(named: "style")
        guard styles.count <= 256 else {
            throw HwpError.invalidXML(
                entry: mapping.entry,
                reason: "style definitions exceed the 256-entry reference space"
            )
        }
        mapping.idMappings.styleArray = try styles
            .map {
                try HwpxParaShapeMapper.mapStyle(
                    $0, tables: mapping.idTables, entry: mapping.entry
                )
            }
        for style in styles {
            mapping.demoteUnconsumed(in: style, consumed: [])
        }
    }

    static func demoteUnconsumedFamilyChildren(
        in family: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) {
        guard let definitionName = definitionNames[family.localName] else {
            return
        }
        // 이름이 같은 타 vocabulary 디코이와 이름이 다른 미래 자식을 한
        // 술어로 강등한다 — 진짜 정의(head)만 소비로 남는다. 이름이 같은
        // 자식만 잡으면 <hh:newDefinition> 같은 미래 자식이 사라진다.
        mapping.demoteUnconsumed(
            in: family, consumed: [definitionName], namespace: HwpxNamespace.head
        )
    }

    /// `hh:charProperties` 가족을 글자 모양 배열로 옮긴다.
    ///
    /// `mapCharShape`가 소비하지 않는 자식은 진단으로 강등해야 "미해석
    /// 강등은 진단으로 보고됨" 규약이 지켜진다 (borderFill·paraPr와 같은 채널).
    static func mapCharProperties(
        _ family: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        let charPrs = family.headChildren(named: "charPr")
        // 스타일의 charShapeId는 0-based UInt16 — 65,537번째부터 그 참조만
        // 65,535로 접힌다. run 참조(paraCharShape.shapeId)는 UInt32라 온전해
        // 같은 문서 안에서 두 참조가 어긋난다 (tabPr·font 가드와 같은 계열).
        guard charPrs.count <= 65536 else {
            throw HwpError.invalidXML(
                entry: mapping.entry,
                reason: "charPr definitions exceed the 65,536-entry reference space"
            )
        }
        mapping.idMappings.charShapeArray = charPrs
            .map { HwpxCharShapeMapper.mapCharShape($0, tables: mapping.idTables) }
        for charPr in charPrs {
            mapping.demoteUnconsumed(
                in: charPr, consumed: Set(Self.charPrLeafNames),
                namespace: HwpxNamespace.head
            )
            // 잎은 전부 단일 조회라 둘째 등장부터는 읽히지 않는다.
            mapping.demoteDuplicateSingletons(
                in: charPr, of: Self.charPrLeafNames, namespace: HwpxNamespace.head
            )
            // 잎 래퍼 15종은 속성만 읽는다 — 자식이 전부 미소비다.
            for leafName in Self.charPrLeafNames {
                if let leaf = charPr.headFirstChild(named: leafName) {
                    mapping.demoteUnconsumed(in: leaf, consumed: [])
                }
            }
        }
    }

    static let charPrLeafNames = [
        "fontRef", "ratio", "spacing", "relSz", "offset", "bold", "italic",
        "emboss", "engrave", "supscript", "subscript", "underline",
        "strikeout", "outline", "shadow",
    ]

    /// 가족 → 정의 요소 이름. `headChildren` 조회가 거른 타 vocabulary
    /// 디코이를 강등할 때 쓴다.
    /// `hh:borderFill` 자식의 기대 vocabulary — 테두리 4종은 head, 채우기는
    /// core다 (전 픽스처 실측: 테두리 각 38건 `hh:`, fillBrush·winBrush 각
    /// 17건 `hc:`). 한쪽으로 통일하면 반드시 다른 쪽이 진단에서 오보된다.
    static let borderFillChildNamespaces: [String: String] = [
        "leftBorder": HwpxNamespace.head,
        "rightBorder": HwpxNamespace.head,
        "topBorder": HwpxNamespace.head,
        "bottomBorder": HwpxNamespace.head,
        "fillBrush": HwpxNamespace.core,
    ]

    static let definitionNames: [String: String] = [
        "fontfaces": "fontface", "borderFills": "borderFill",
        "charProperties": "charPr", "tabProperties": "tabPr",
        "numberings": "numbering", "bullets": "bullet",
        "paraProperties": "paraPr", "styles": "style",
    ]

    /// `hh:numberings` 가족을 문단 번호 배열로 옮긴다.
    ///
    /// 수준 슬롯을 얻지 못한 `hh:paraHead`(중복 수준·1-10 밖 수준)는 진단으로
    /// 강등해야 "미해석 강등은 진단으로 보고됨" 규약이 지켜진다.
    static func mapNumberings(
        _ family: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        let numberings = family.headChildren(named: "numbering")
        // 번호 참조는 1-based UInt16 (0 = 없음) — borderFill과 같은 계열이라
        // 65,536번째 정의부터 `numberingOrBulletId`의 offset + 1 클램프가
        // 직전 정의로 별칭화한다.
        guard numberings.count <= 65535 else {
            throw HwpError.invalidXML(
                entry: mapping.entry,
                reason: "numbering definitions exceed the 65,535-entry reference space"
            )
        }
        var mapped: [HwpNumbering] = []
        var rejected: [[Int]] = []
        for numbering in numberings {
            let definition = HwpxNumberingMapper.mapNumbering(
                numbering, tables: mapping.idTables
            )
            // 번호 형식 문자열은 표 38이 WORD 길이 + WCHAR×len으로 적는다 —
            // 65,535 단위를 넘으면 `HwpNumberingFormat`의 길이만 접히고 문자열은
            // 남아 "길이 == 문자 수" 불변식이 깨진 모델이 나간다. 절단은
            // 서러게이트 쌍을 가르므로 typed error로 거부한다
            // (`HwpxParagraphMapper`·`HwpxTableMapper`의 카운트 불변식 가드와
            // 같은 처방). 검사는 **수준 슬롯을 얻은 형식만** 본다 — 중복 수준과
            // 1-10 밖 수준의 `hh:paraHead`는 형식이 되지 않으므로 불변식을
            // 깨뜨릴 수 없고, 문서를 거부하는 대신 진단으로 강등하는 것이 규약이다.
            guard Self.formatLengthsAreConsistent(definition.numbering) else {
                throw HwpError.invalidXML(
                    entry: mapping.entry,
                    reason: "numbering format text exceeds the 65,535 UTF-16 unit length field"
                )
            }
            mapped.append(definition.numbering)
            rejected.append(definition.rejectedParaHeadIndices)
        }
        mapping.idMappings.numberingArray = mapped
        for (numbering, rejectedIndices) in zip(numberings, rejected) {
            demoteParaHeads(in: numbering, rejected: rejectedIndices, into: &mapping)
        }
    }

    /// `formatLength == format.utf16.count` — 바이너리 로더가 길이 필드만큼
    /// WCHAR를 정확히 읽어 보장하는 불변식이다.
    static func formatLengthsAreConsistent(_ numbering: HwpNumbering) -> Bool {
        (numbering.formatArray + (numbering.extendedFormatArray ?? []))
            .allSatisfy { Int($0.formatLength) == $0.format.utf16.count }
    }

    /// `hh:bullets` 가족을 글머리표 배열로 옮긴다.
    static func mapBullets(
        _ family: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        let bullets = family.headChildren(named: "bullet")
        // 글머리표 참조도 1-based UInt16이다 (문단 모양이 번호와 같은 필드를
        // 쓰고 머리 종류로 어느 배열인지 가른다).
        guard bullets.count <= 65535 else {
            throw HwpError.invalidXML(
                entry: mapping.entry,
                reason: "bullet definitions exceed the 65,535-entry reference space"
            )
        }
        var mapped: [HwpBullet] = []
        var rejected: [[Int]] = []
        for bullet in bullets {
            let definition = HwpxNumberingMapper.mapBullet(bullet, tables: mapping.idTables)
            mapped.append(definition.bullet)
            rejected.append(definition.rejectedParaHeadIndices)
        }
        mapping.idMappings.bulletArray = mapped
        for (bullet, rejectedIndices) in zip(bullets, rejected) {
            demoteParaHeads(in: bullet, rejected: rejectedIndices, into: &mapping)
        }
    }

    /// 정의 하나의 자식 강등 — 소비된 `hh:paraHead`는 그 안의 미지 자식만,
    /// 슬롯을 얻지 못한 것은 서브트리째 남긴다 (같은 노드를 두 번 싣지 않는다).
    static func demoteParaHeads(
        in definition: HwpxXMLNode,
        rejected: [Int],
        into mapping: inout HwpxHeaderMapping
    ) {
        mapping.demoteUnconsumed(
            in: definition, consumed: ["paraHead"], namespace: HwpxNamespace.head
        )
        let rejectedIndices = Set(rejected)
        for (index, paraHead) in definition.headChildren(named: "paraHead").enumerated() {
            if rejectedIndices.contains(index) {
                mapping.demote(paraHead)
            } else {
                mapping.demoteUnconsumed(in: paraHead, consumed: [])
            }
        }
    }

    /// `hh:tabProperties` 가족을 탭 정의 배열로 옮긴다.
    ///
    /// 명시 탭 정지(`hh:tabItem`)는 1차 범위 밖이라 `mapTabDef`가 속성만
    /// 옮긴다 — 버려지는 자식은 진단으로 강등해야 "미해석 강등은 진단으로
    /// 보고됨" 규약이 지켜진다 (numbering/bullet의 가족 수준 강등과 같은 채널).
    static func mapTabProperties(
        _ family: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        let tabPrs = family.headChildren(named: "tabPr")
        // 문단 tabDefId는 0-based UInt16 — 65,537번째부터 오프셋이 65,535로
        // 별칭화된다 (paraPr 65,536 가드와 같은 계열).
        guard tabPrs.count <= 65536 else {
            throw HwpError.invalidXML(
                entry: mapping.entry,
                reason: "tabPr definitions exceed the 65,536-entry reference space"
            )
        }
        mapping.idMappings.tabDefArray = tabPrs.map(HwpxParaShapeMapper.mapTabDef)
        for tabPr in tabPrs {
            for child in tabPr.childElements {
                mapping.demote(child)
            }
        }
    }

    /// `hh:borderFills` 가족을 테두리/배경 배열로 옮긴다.
    ///
    /// `mapBorderFill`은 4방향 테두리와 단색 채우기만 소비한다 — slash 계열
    /// 테두리·그러데이션/이미지 채우기 등 미소비 자손은 진단으로 강등해야
    /// "미해석 강등은 진단으로 보고됨" 규약이 지켜진다.
    static func mapBorderFills(
        _ family: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        let borderFills = family.headChildren(named: "borderFill")
        // borderFill 참조는 1-based UInt16 (0 = 없음) — 표현 공간이 65,535라
        // 65,536번째 정의부터 `borderFillId`의 offset + 1 클램프가 직전
        // 정의로 별칭화한다 (스타일 256·paraPr 65,536 가드와 같은 계열,
        // 1-based라 상한만 1 작다).
        guard borderFills.count <= 65535 else {
            throw HwpError.invalidXML(
                entry: mapping.entry,
                reason: "borderFill definitions exceed the 65,535-entry reference space"
            )
        }
        mapping.idMappings.borderFillArray = borderFills.map(HwpxParaShapeMapper.mapBorderFill)
        for borderFill in borderFills {
            mapping.demoteUnconsumed(
                in: borderFill, consumed: Self.borderFillChildNamespaces
            )
            mapping.demoteDuplicateSingletons(
                in: borderFill, of: Self.borderFillChildNamespaces
            )
            for borderName in ["leftBorder", "rightBorder", "topBorder", "bottomBorder"] {
                if let border = borderFill.headFirstChild(named: borderName) {
                    mapping.demoteUnconsumed(in: border, consumed: [])
                }
            }
            if let fillBrush = borderFill.coreFirstChild(named: "fillBrush") {
                mapping.demoteUnconsumed(
                    in: fillBrush, consumed: ["winBrush"], namespace: HwpxNamespace.core
                )
                mapping.demoteDuplicateSingletons(
                    in: fillBrush, of: ["winBrush"], namespace: HwpxNamespace.core
                )
                if let winBrush = fillBrush.coreFirstChild(named: "winBrush") {
                    mapping.demoteUnconsumed(in: winBrush, consumed: [])
                }
            }
        }
    }

    /// `hh:paraProperties` 가족을 문단 모양 배열로 옮긴다.
    ///
    /// breakSetting·autoSpacing 등 1차 범위 밖 자식은 `mapParaShape`가 속성만
    /// 옮기고 버린다 — 진단으로 강등해야 "미해석 강등은 진단으로 보고됨"
    /// 규약이 지켜진다 (tabPr의 tabItem 강등과 같은 채널).
    static func mapParaProperties(
        _ family: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        let paraPrs = family.headChildren(named: "paraPr")
        // 문단 paraShapeId는 UInt16 — 65,537번째부터 오프셋이 65,535로
        // 별칭화되므로 정의 수를 참조 공간으로 제한한다 (스타일 256 가드와
        // 같은 계열).
        guard paraPrs.count <= 65536 else {
            throw HwpError.invalidXML(
                entry: mapping.entry,
                reason: "paraPr definitions exceed the 65,536-entry reference space"
            )
        }
        mapping.idMappings.paraShapeArray = paraPrs
            .map { HwpxParaShapeMapper.mapParaShape($0, tables: mapping.idTables) }
        for paraPr in paraPrs {
            mapping.demoteUnconsumed(
                in: paraPr,
                consumed: ["align", "heading", "margin", "lineSpacing", "border"],
                namespace: HwpxNamespace.head
            )
            mapping.demoteDuplicateSingletons(
                in: paraPr,
                of: ["align", "heading", "margin", "lineSpacing", "border"],
                namespace: HwpxNamespace.head
            )
            // 소비된 래퍼 안 미지 자식 — margin은 5종만 읽고 나머지 래퍼
            // 4종은 속성만 읽는 잎이라 자식이 전부 미소비다.
            if let margin = paraPr.headFirstChild(named: "margin") {
                mapping.demoteUnconsumed(
                    in: margin,
                    consumed: ["intent", "left", "right", "prev", "next"],
                    namespace: HwpxNamespace.core
                )
                mapping.demoteDuplicateSingletons(
                    in: margin,
                    of: ["intent", "left", "right", "prev", "next"],
                    namespace: HwpxNamespace.core
                )
                for valueName in ["intent", "left", "right", "prev", "next"] {
                    if let value = margin.coreFirstChild(named: valueName) {
                        mapping.demoteUnconsumed(in: value, consumed: [])
                    }
                }
            }
            for leafName in ["align", "heading", "lineSpacing", "border"] {
                if let leaf = paraPr.headFirstChild(named: leafName) {
                    mapping.demoteUnconsumed(in: leaf, consumed: [])
                }
            }
        }
    }

    static func register(
        _ family: HwpxXMLNode,
        _ childName: String,
        into table: inout HwpxIdTable
    ) {
        for (offset, child) in family.headChildren(named: childName).enumerated() {
            table.register(id: child.attribute("id"), offset: offset)
        }
    }
}

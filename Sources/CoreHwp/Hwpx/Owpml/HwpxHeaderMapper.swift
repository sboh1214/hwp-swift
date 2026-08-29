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
func hwpxValidateNameLength(_ name: String) throws {
    guard name.utf16.count <= Int(WORD.max) else {
        throw HwpError.invalidXML(
            entry: HwpxContainer.EntryName.header,
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
}

enum HwpxHeaderMapper {
    static func map(
        _ data: Data,
        binDataCatalog: HwpxBinDataCatalog,
        options: HwpLoadOptions,
        sectionCount: Int? = nil
    ) throws -> (docInfo: HwpDocInfo, idTables: HwpxIdTables) {
        let entry = HwpxContainer.EntryName.header
        let root = try HwpxXMLTreeParser.parse(data, entry: entry)
        guard root.isNamed("head", in: HwpxNamespace.head) else {
            throw HwpError.invalidXML(
                entry: entry,
                reason: "unexpected root element <\(root.localName)>"
            )
        }

        var mapping = HwpxHeaderMapping()
        // 실재 구역 수(조립기가 셈)가 secCnt 선언보다 정확하다 — 선언이
        // 어긋난 문서에서 모델 내부 일관성을 지킨다.
        mapping.documentProperties.sectionSize = UInt16(
            clamping: sectionCount ?? root.intAttribute("secCnt", default: 1)
        )

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
        for child in root.childElements {
            if child.isNamed("beginNum") {
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
            } else if child.isNamed("refList") {
                try mapRefList(child, into: &mapping)
            } else {
                mapping.unknownRecords.append(unknownRecord(of: child))
            }
        }
    }

    static func mapRefList(
        _ refList: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) throws {
        // 1차 패스: 가족별 id 테이블 등록 — 가족 사이 참조(글자→테두리,
        // 스타일→문단/글자, 문단→탭/번호)가 문서 내 등장 순서와 무관하게
        // 해석되도록 등록을 먼저 끝낸다.
        for family in refList.childElements {
            switch family.localName {
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

        // 2차 패스: 모델 매핑.
        for family in refList.childElements {
            guard family.isNamed(family.localName) else {
                mapping.unknownRecords.append(unknownRecord(of: family))
                continue
            }
            switch family.localName {
            case "fontfaces":
                try HwpxCharShapeMapper.mapFontFaces(
                    family, into: &mapping.idMappings, tables: &mapping.idTables
                )
            case "borderFills":
                mapping.idMappings.borderFillArray = family.children(named: "borderFill")
                    .map(HwpxParaShapeMapper.mapBorderFill)
            case "charProperties":
                mapping.idMappings.charShapeArray = family.children(named: "charPr")
                    .map { HwpxCharShapeMapper.mapCharShape($0, tables: mapping.idTables) }
            case "tabProperties":
                mapping.idMappings.tabDefArray = family.children(named: "tabPr")
                    .map(HwpxParaShapeMapper.mapTabDef)
            case "paraProperties":
                mapping.idMappings.paraShapeArray = family.children(named: "paraPr")
                    .map { HwpxParaShapeMapper.mapParaShape($0, tables: mapping.idTables) }
            case "styles":
                mapping.idMappings.styleArray = try family.children(named: "style")
                    .map { try HwpxParaShapeMapper.mapStyle($0, tables: mapping.idTables) }
            case "numberings", "bullets":
                // 1차 범위 밖 — id 테이블만 등록해 참조가 결정적으로
                // 재작성되게 하고, 미해석 사실은 진단에 남긴다 (배열이
                // 비어 있으므로 조판은 번호 없이 그린다).
                mapping.unknownRecords.append(unknownRecord(of: family))
            default:
                mapping.unknownRecords.append(unknownRecord(of: family))
            }
        }
    }

    static func register(
        _ family: HwpxXMLNode,
        _ childName: String,
        into table: inout HwpxIdTable
    ) {
        for (offset, child) in family.children(named: childName).enumerated() {
            table.register(id: child.attribute("id"), offset: offset)
        }
    }

    static func unknownRecord(of node: HwpxXMLNode) -> HwpUnknownRecord {
        HwpUnknownRecord(
            tagId: hwpxSyntheticTagId,
            level: 0,
            payload: Data(node.localName.utf8)
        )
    }
}

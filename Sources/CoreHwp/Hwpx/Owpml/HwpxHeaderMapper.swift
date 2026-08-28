import Foundation

/// XML에서 온 요소를 진단에 실을 때 쓰는 합성 tag id.
///
/// 실제 HWP5 태그 공간(0x10 이상)과 겹치지 않는 0을 세워 두고, 요소 이름을
/// UTF-8로 payload에 싣는다 — `parseDiagnostics()`의 `unknownRecord` 경로가
/// 무변경으로 HWPX 미해석 요소를 보고하게 하는 규약이다 (tagId 0 + payload =
/// OWPML local name).
let hwpxSyntheticTagId: UInt32 = 0

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
        options: HwpLoadOptions
    ) throws -> (docInfo: HwpDocInfo, idTables: HwpxIdTables) {
        let entry = HwpxContainer.EntryName.header
        let root = try HwpxXMLTreeParser.parse(data, entry: entry)
        guard root.isNamed("head") else {
            throw HwpError.invalidXML(
                entry: entry,
                reason: "unexpected root element <\(root.localName)>"
            )
        }

        var mapping = HwpxHeaderMapping()
        mapping.documentProperties.sectionSize = UInt16(
            clamping: root.intAttribute("secCnt", default: 1)
        )

        // 빈 문서 기본값에서 출발하되, 매핑 대상 가족은 전부 덮어쓴다 —
        // 기본값 항목이 리맵된 오프셋 공간에 섞이면 참조가 어긋난다.
        mapping.idMappings.binDataArray = binDataCatalog.binDataArray
        mapping.idMappings.faceNameKoreanArray = []
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

        mapHeadChildren(root, into: &mapping)

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
    ) {
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
                mapRefList(child, into: &mapping)
            } else {
                mapping.unknownRecords.append(unknownRecord(of: child))
            }
        }
    }

    static func mapRefList(
        _ refList: HwpxXMLNode,
        into mapping: inout HwpxHeaderMapping
    ) {
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
                HwpxCharShapeMapper.mapFontFaces(
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
                mapping.idMappings.styleArray = family.children(named: "style")
                    .map { HwpxParaShapeMapper.mapStyle($0, tables: mapping.idTables) }
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

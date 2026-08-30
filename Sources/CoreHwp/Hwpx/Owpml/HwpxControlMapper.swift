import Foundation

/// run 자식 요소 하나를 WCHAR 스트림 항목으로 분류한 결과.
///
/// **불변식**: `.anchor`만 extended 문자와 ctrl 슬롯을 동시에 만든다 —
/// `HwpTextRunBuilder`의 `extendedOrdinal`이 모든 extended 문자를 세며
/// `ctrlHeaderArray`를 서수로 직접 인덱싱하므로, extended 문자 없는 ctrl도
/// ctrl 없는 extended 문자도 정렬을 무너뜨린다.
enum HwpxRunChildAction {
    /// extended 제어 문자(코드) + 컨트롤 — 둘이 동시에 추가된다.
    case anchor(code: UInt16, fourCC: UInt32, ctrl: HwpCtrlId)
    /// inline 제어 문자 — ctrl 슬롯을 만들지 않는다 (필드 끝 코드 4).
    case inlineOnly(code: UInt16, fourCC: UInt32)
    /// 위치를 차지하지 않는 메타 요소 — 진단만 남기고 건너뛴다.
    case zeroWidth
    /// 미지 요소 — 앵커를 추측하지 않는다 (위치 불확실 → lineseg 폐기).
    case unknown
}

/// `hp:run`/`hp:ctrl` 자식 요소 → HWP5 제어 문자·컨트롤 대응표.
enum HwpxControlMapper {
    static func classify(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpxRunChildAction {
        // paragraph vocabulary가 아닌 동명 요소(`<ext:tbl>` 등)를 OWPML 컨트롤로
        // 합성하면 WCHAR/컨트롤 스트림이 어긋난다 — local-name switch 전에
        // namespace로 거른다 (P2). 낯선 요소는 앵커를 추측하지 않는다.
        guard node.namespaceURI.isEmpty || node.namespaceURI == HwpxNamespace.paragraph else {
            return .unknown
        }
        switch node.localName {
        case "secPr":
            return .anchor(
                code: 2,
                fourCC: HwpOtherCtrlId.section.rawValue,
                ctrl: .section(HwpxSecPrMapper.mapSectionDef(node))
            )
        case "colPr":
            return .anchor(
                code: 2,
                fourCC: HwpOtherCtrlId.column.rawValue,
                ctrl: .column(HwpxSecPrMapper.mapColumn(node))
            )
        case "fieldBegin":
            let fourCC = fieldFourCC(of: node.attribute("type"))
            return .anchor(
                code: 3,
                fourCC: fourCC,
                ctrl: degradedControl(fourCC: fourCC, element: node)
            )
        case "fieldEnd":
            return .inlineOnly(code: 4, fourCC: HwpFieldCtrlId.unknown.rawValue)
        case "tbl":
            return .anchor(
                code: 11,
                fourCC: HwpCommonCtrlId.table.rawValue,
                ctrl: .table(try HwpxTableMapper.map(node, context: context))
            )
        case "pic":
            return .anchor(
                code: 11,
                fourCC: HwpCommonCtrlId.picture.rawValue,
                ctrl: .picture(HwpxPictureMapper.map(node, context: context))
            )
        default:
            return classifyAnchorObject(node)
        }
    }

    /// 미구현 개체·구역 부속 요소 — 전부 미구현 강등이되 4CC는 실제 값을
    /// 실어 `parseDiagnostics()`가 `notImplementedControl`로 종류까지
    /// 보고한다.
    private static func classifyAnchorObject(_ node: HwpxXMLNode) -> HwpxRunChildAction {
        if let fourCC = objectFourCCs[node.localName] {
            return .anchor(
                code: 11,
                fourCC: fourCC,
                ctrl: degradedControl(fourCC: fourCC, element: node)
            )
        }
        if let (code, fourCC) = sectionAttachments[node.localName] {
            return .anchor(
                code: code,
                fourCC: fourCC,
                ctrl: degradedControl(fourCC: fourCC, element: node)
            )
        }
        return .unknown
    }

    /// 미구현 컨트롤 강등 — 요소 이름을 header payload와 unknownChildren에
    /// 함께 실어 진단이 OWPML 이름까지 보존한다 (`.notImplemented`의
    /// unknownChildren은 diagnostics walker가 걷는다).
    static func degradedControl(fourCC: UInt32, element: HwpxXMLNode) -> HwpCtrlId {
        .notImplemented(HwpCtrlHeader(
            ctrlId: fourCC,
            rawPayload: Data(element.localName.utf8),
            unknownChildren: [element.syntheticUnknownRecord()]
        ))
    }

    /// 코드 11(개체 앵커)로 자리하는 미구현 요소들의 4CC (tbl·pic은 위에서
    /// typed 매핑으로 승격됐다).
    static let objectFourCCs: [String: UInt32] = [
        "ole": HwpCommonCtrlId.ole.rawValue,
        "equation": HwpCommonCtrlId.equation.rawValue,
        "line": HwpCommonCtrlId.line.rawValue,
        "rect": HwpCommonCtrlId.rectangle.rawValue,
        "ellipse": HwpCommonCtrlId.ellipse.rawValue,
        "arc": HwpCommonCtrlId.arc.rawValue,
        "polygon": HwpCommonCtrlId.polygon.rawValue,
        "curve": HwpCommonCtrlId.curve.rawValue,
        "connectLine": HwpCommonCtrlId.line.rawValue,
        "textart": HwpCommonCtrlId.genShapeObject.rawValue,
        "container": HwpCommonCtrlId.container.rawValue,
        "video": HwpCommonCtrlId.genShapeObject.rawValue,
    ]

    /// 개체가 아닌 구역 부속 컨트롤 — (제어 문자 코드, 4CC).
    static let sectionAttachments: [String: (code: UInt16, fourCC: UInt32)] = [
        "header": (16, HwpOtherCtrlId.header.rawValue),
        "footer": (16, HwpOtherCtrlId.footer.rawValue),
        "footNote": (17, HwpOtherCtrlId.footnote.rawValue),
        "endNote": (17, HwpOtherCtrlId.endnote.rawValue),
        "autoNum": (18, HwpOtherCtrlId.autoNumber.rawValue),
        "newNum": (18, HwpOtherCtrlId.newNumber.rawValue),
        "pageNum": (21, HwpOtherCtrlId.pageNumberPosition.rawValue),
        "pageNumCtrl": (21, HwpOtherCtrlId.pageCT.rawValue),
        "pageHiding": (21, HwpOtherCtrlId.pageHide.rawValue),
        "bookmark": (22, HwpOtherCtrlId.bookmark.rawValue),
        "indexmark": (22, HwpOtherCtrlId.indexmark.rawValue),
    ]

    /// `hp:fieldBegin type` → HWP5 필드 4CC. 미지 유형은 `%unk`.
    static func fieldFourCC(of type: String?) -> UInt32 {
        switch type {
        case "HYPERLINK":
            HwpFieldCtrlId.hyperLink.rawValue
        default:
            HwpFieldCtrlId.unknown.rawValue
        }
    }
}

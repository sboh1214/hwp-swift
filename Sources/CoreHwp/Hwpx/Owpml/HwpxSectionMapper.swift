import Foundation

/// `Contents/section{N}.xml`(`hs:sec`) 하나를 `HwpSection`으로 옮긴다.
///
/// 복구 규약은 바이너리 `HwpSection.init`과 같다: `recoverPartialContent`가
/// 켜지면 손상 문단을 placeholder로 대체하되 **구역의 첫 문단은 예외**로
/// 전파한다 — secPr(구역 정의)은 첫 문단에만 붙고 paginator는 sectionDef
/// 하나로만 구역 경계를 인식하므로, 첫 문단을 삼키면 그 구역이 앞 구역의
/// 지오메트리로 조판된다 (#110과 같은 근거). 전파된 오류는 상위(HwpFile
/// 조립)가 구역 단위 placeholder로 승격시킨다.
enum HwpxSectionMapper {
    static func map(
        _ data: Data,
        context: HwpxMappingContext
    ) throws -> HwpSection {
        let root = try HwpxXMLTreeParser.parse(data, entry: context.entry)
        guard root.isNamed("sec", in: HwpxNamespace.section) else {
            throw HwpError.invalidXML(
                entry: context.entry,
                reason: "unexpected root element <\(root.localName)>"
            )
        }

        var paragraphs: [HwpParagraph] = []
        var unknownRecords: [HwpUnknownRecord] = []
        // 본문 문단은 정의상 hp:p뿐 — 전역 known 집합으로 매칭하면 다른
        // known vocabulary의 동명 요소(hh:p)가 문단으로 오인되면서 unknown
        // 보고에서도 빠진다 ((namespace, local name) 매칭 규약).
        let isParagraph = { (node: HwpxXMLNode) in
            node.isNamed("p", in: HwpxNamespace.paragraph)
        }
        let paragraphNodes = root.childElements.filter(isParagraph)
        for child in root.childElements where !isParagraph(child) {
            unknownRecords.append(child.syntheticUnknownRecord())
        }

        for (index, node) in paragraphNodes.enumerated() {
            let isLast = index == paragraphNodes.count - 1
            do {
                paragraphs.append(try HwpxParagraphMapper.map(
                    node, context: context, isLastInList: isLast
                ))
            } catch let error as HwpError
                where index > 0
                && context.options.recoverPartialContent && !error.isRecoveryExempt
            {
                paragraphs.append(Self.paragraphPlaceholder(error: error))
            }
        }

        guard !paragraphs.isEmpty else {
            throw HwpError.invalidXML(
                entry: context.entry, reason: "section has no paragraphs"
            )
        }
        // 구역 첫 문단은 sectionDef를 실어야 한다 — paginator는 sectionDef(in:)
        // 하나로만 구역 경계를 인식하므로, 없으면 이 구역이 앞 구역의 기하로
        // 조판되고 뒤 문단의 secPr는 유령 경계를 만든다. 복구 모드에선 구역
        // placeholder가 이 전제를 지킨다 (#110의 구역 단위 처리와 같은 근거).
        let hasLeadingSectionDef = paragraphs[0].ctrlHeaderArray?.contains { ctrl in
            if case .section = ctrl {
                return true
            }
            return false
        } ?? false
        guard hasLeadingSectionDef else {
            throw HwpError.invalidXML(
                entry: context.entry,
                reason: "section's first paragraph lacks secPr"
            )
        }

        var section = HwpSection()
        section.rawPayload = context.options.preservedPayload(data)
        section.paragraph = paragraphs
        section.unknownRecords = unknownRecords
        section.parseFailure = nil
        return section
    }

    /// XML 문단 placeholder — 바이너리 `parseFailurePlaceholder`와 같은 형태
    /// (`paraText = nil` → run builder가 빈 문단으로 처리, 원인은
    /// `parseFailure`에, 요소 표식은 `unknownChildren`에).
    static func paragraphPlaceholder(error: HwpError) -> HwpParagraph {
        var paragraph = HwpParagraph()
        paragraph.paraText = nil
        paragraph.unknownChildren = [HwpUnknownRecord(
            tagId: hwpxSyntheticTagId, level: 0, payload: Data("p".utf8)
        )]
        paragraph.parseFailure = String(describing: error)
        return paragraph
    }
}

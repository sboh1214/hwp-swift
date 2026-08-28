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
        guard root.isNamed("sec") else {
            throw HwpError.invalidXML(
                entry: context.entry,
                reason: "unexpected root element <\(root.localName)>"
            )
        }

        var paragraphs: [HwpParagraph] = []
        var unknownRecords: [HwpUnknownRecord] = []
        let paragraphNodes = root.childElements.filter { $0.isNamed("p") }
        for child in root.childElements where !child.isNamed("p") {
            unknownRecords.append(HwpUnknownRecord(
                tagId: hwpxSyntheticTagId, level: 0, payload: Data(child.localName.utf8)
            ))
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

@testable import CoreHwp
import Foundation
@testable import HwpKitCore

/// 합성 CoreHwp 모델 빌더 — paginator 통합 테스트 전용.
enum HwpSynthetic {
    /// UTF-16LE로 인코딩한 PARA_TEXT payload
    static func utf16Data(_ text: String) -> Data {
        var data = Data()
        for unit in text.utf16 {
            withUnsafeBytes(of: unit.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// 지정한 텍스트 한 줄을 가진 문단 (라인 세그먼트 캐시 없음 → CT 레이아웃 사용)
    static func textParagraph(_ text: String) throws -> CoreHwp.HwpParagraph {
        var paragraph = CoreHwp.HwpParagraph()
        paragraph.paraText = try CoreHwp.HwpParaText.load(utf16Data(text))
        return paragraph
    }

    /// 머리말/꼬리말/각주/미주 리스트 컨트롤.
    /// ctrl 헤더 payload는 ctrl id + 속성 u32 (표 140 prefix 레이아웃).
    static func listControl(
        ctrlId: CoreHwp.HwpOtherCtrlId,
        property: UInt32 = 0,
        paragraphs: [CoreHwp.HwpParagraph]
    ) -> CoreHwp.HwpListControl {
        var payload = Data()
        withUnsafeBytes(of: ctrlId.rawValue.littleEndian) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: property.littleEndian) { payload.append(contentsOf: $0) }
        return CoreHwp.HwpListControl(
            header: CoreHwp.HwpCtrlHeader(ctrlId: ctrlId.rawValue, rawPayload: payload),
            listArray: [CoreHwp.HwpListControlList(
                header: CoreHwp.HwpListHeader(),
                headerRawPayload: Data(),
                headerUnknownChildren: [],
                paragraphArray: paragraphs
            )],
            unknownChildren: []
        )
    }

    /// 리스트 컨트롤을 HwpCtrlId 케이스로 감싼다.
    static func wrapped(
        _ control: CoreHwp.HwpListControl,
        as ctrlId: CoreHwp.HwpOtherCtrlId
    ) -> CoreHwp.HwpCtrlId? {
        switch ctrlId {
        case .header: .header(control)
        case .footer: .footer(control)
        case .footnote: .footnote(control)
        case .endnote: .endnote(control)
        default: nil
        }
    }

    /// 페이지 크기를 지정한 구역 정의 (단위: HWPUNIT)
    static func sectionDef(
        pageWidth: UInt32 = 59528,
        pageHeight: UInt32 = 84188
    ) -> CoreHwp.HwpSectionDef {
        var sectionDef = CoreHwp.HwpSectionDef()
        sectionDef.pageDef.width = pageWidth
        sectionDef.pageDef.height = pageHeight
        return sectionDef
    }

    /// 빈 문서의 첫 구역을 기반으로, 첫 문단 컨트롤과 본문 문단을 구성한 구역을 만든다.
    static func section(
        firstParagraphControls: [CoreHwp.HwpCtrlId],
        bodyParagraphs: [CoreHwp.HwpParagraph]
    ) -> CoreHwp.HwpSection {
        let file = CoreHwp.HwpFile()
        var section = file.sectionArray[0]
        var first = section.paragraph[0]
        first.ctrlHeaderArray = firstParagraphControls
        section.paragraph[0] = first
        section.paragraph.append(contentsOf: bodyParagraphs)
        return section
    }
}

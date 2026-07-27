@testable import CoreHwp
import Foundation
@testable import HwpKitCore

/// 번호/쪽 크롬 관련 합성 빌더 (자동 번호, 새 번호, 쪽 번호 위치, 쪽 감추기)
extension HwpSynthetic {
    /// 자동 번호 (atno, 표 142/143) 컨트롤.
    /// kind: 0 쪽, 1 각주, 2 미주. decorationTail 예: ")".
    static func autoNumberControl(
        kind: UInt32,
        number: UInt16 = 1,
        numberShape: UInt32 = 0,
        decorationTail: Character? = nil,
        superscript: Bool = false
    ) -> CoreHwp.HwpCtrlId {
        var property = (kind & 0xF) | ((numberShape & 0xFF) << 4)
        if superscript {
            property |= 1 << 12
        }
        let info = CoreHwp.HwpOtherControlAutoNumberInfo(
            property: property,
            number: number,
            userSymbol: 0,
            decorationHead: 0,
            decorationTail: decorationTail?.utf16.first ?? 0,
            rawTrailing: Data()
        )
        return .autoNumber(CoreHwp.HwpOtherControl(
            ctrlId: .autoNumber,
            rawTrailing: Data(),
            rawPayload: Data(),
            ctrlDataRecords: [],
            unknownChildren: [],
            autoNumberInfo: info
        ))
    }

    /// 새 번호 지정 (nwno, 표 144) 컨트롤. kind: 표 143 번호 종류.
    static func newNumberControl(kind: UInt32, number: UInt16) -> CoreHwp.HwpCtrlId {
        .newNumber(CoreHwp.HwpOtherControl(
            ctrlId: .newNumber,
            rawTrailing: Data(),
            rawPayload: Data(),
            ctrlDataRecords: [],
            unknownChildren: [],
            newNumberInfo: CoreHwp.HwpOtherControlNewNumberInfo(
                property: kind & 0xF,
                number: number,
                rawTrailing: Data()
            )
        ))
    }

    /// [ext18 자동 번호] 마커로 시작하는 각주/미주 문단 (한/글 저장 구조와 동일)
    static func noteParagraph(
        _ text: String,
        autoNumber: CoreHwp.HwpCtrlId
    ) -> CoreHwp.HwpParagraph {
        var paragraph = CoreHwp.HwpParagraph()
        var paraText = CoreHwp.HwpParaText()
        paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 18)]
            + text.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
        paragraph.paraText = paraText
        paragraph.paraLineSeg.paraLineSegInternalArray = []
        paragraph.ctrlHeaderArray = [autoNumber]
        return paragraph
    }

    /// 쪽 번호 위치 (pgNumPos, 표 147/148) 컨트롤.
    /// displayPosition: 0 없음, 1~3 위 (좌/중/우), 4~6 아래 (좌/중/우),
    /// 7/8 바깥쪽, 9/10 안쪽. numberFormat: 표 134 번호 모양.
    static func pageNumberPositionControl(
        numberFormat: Int = 0,
        displayPosition: Int = 5,
        headDecoration: Character? = nil,
        tailDecoration: Character? = nil
    ) -> CoreHwp.HwpCtrlId {
        var property = CoreHwp.HwpPageNumberPositionProperty()
        property.numberFormat = numberFormat
        property.displayPosition = displayPosition
        property.rawValue = UInt32(numberFormat & 0xFF)
            | (UInt32(displayPosition & 0xF) << 8)
        return .pageNumberPosition(CoreHwp.HwpPageNumberPosition(
            otherCtrlId: .pageNumberPosition,
            property: property.rawValue,
            propertyInfo: property,
            userSymbol: 0,
            headDecoration: headDecoration?.utf16.first ?? 0,
            tailDecoration: tailDecoration?.utf16.first ?? 0,
            unused: 0x2D,
            unknown: 0,
            rawPayload: Data(),
            rawTrailing: Data(),
            unknownChildren: []
        ))
    }

    /// 쪽 감추기 (pghd, 표 145) 컨트롤.
    /// mask: 0x01 머리말, 0x02 꼬리말, 0x20 쪽 번호.
    static func pageHideControl(mask: UInt32) -> CoreHwp.HwpCtrlId {
        .pageHide(CoreHwp.HwpOtherControl(
            ctrlId: .pageHide,
            rawTrailing: Data(),
            rawPayload: Data(),
            ctrlDataRecords: [],
            unknownChildren: [],
            pageHideInfo: CoreHwp.HwpOtherControlPageHideInfo(
                rawValue: mask,
                rawTrailing: Data()
            )
        ))
    }

    /// extended 컨트롤 문자 하나만 있는 문단 (nwno/pghd 등 마커 전용 컨트롤)
    static func markerParagraph(control: CoreHwp.HwpCtrlId) -> CoreHwp.HwpParagraph {
        var paragraph = CoreHwp.HwpParagraph()
        var paraText = CoreHwp.HwpParaText()
        paraText.charArray = [CoreHwp.HwpChar(type: .extended, value: 21)]
        paragraph.paraText = paraText
        paragraph.paraLineSeg.paraLineSegInternalArray = []
        paragraph.ctrlHeaderArray = [control]
        return paragraph
    }
}

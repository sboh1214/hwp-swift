@testable import CoreHwp
import Foundation

/// 구역 부속 표식 등가 투영 (#169) — `DocumentEquivalenceProjection`의 표식 축.
///
/// 본체에서 떼어 둔 것은 이 축만 **제어 문자 스트림과 컨트롤 슬롯을 함께**
/// 걷기 때문이다. 다른 축은 컨트롤 배열만 보면 되지만, 여기서는 제어 문자
/// 코드가 축의 일부다 — `nwno`를 코드 18로 적던 오기(승격 전 강등 표)를 잡을
/// 수 있는 것이 이 축뿐이다. 기존 텍스트 축은 `char.value >= 32`로 제어 문자를
/// 전부 걸러내고, `HwpParaHeader.controlMask`에는 소비자가 없다.
extension DocumentEquivalenceProjection {
    /// 새 번호 지정·쪽 감추기·책갈피·찾아보기 표식 하나 (#169).
    ///
    /// 승격 전 HWPX는 넷 다 `.notImplemented`라 `kind`가 전부 `"notImplemented"`로
    /// 접히고 payload에는 OWPML 요소 이름만 들어 있었다 — 그래서 이 축은 강등
    /// 상태와 승격 상태를 구분한다.
    ///
    /// `rawPayload`를 통째로 싣는 이유는 typed 필드만 비교하면 합성 payload가
    /// 실물과 다른 길이·자리여도 통과하기 때문이다 (`indexmarkInfo`는 남는
    /// 바이트를 조용히 `rawTrailing`으로 흘린다). 책갈피는 이름이 컨트롤 payload가
    /// 아니라 `CTRL_DATA` 자식에 있으므로 그 바이트도 함께 싣는다.
    struct SectionMark: Equatable {
        let kind: String
        /// 제어 문자 코드 — 새 번호·쪽 감추기 21, 책갈피·찾아보기 표식 22.
        let controlCharacterCode: UInt16
        let newNumberKind: UInt32?
        let newNumberValue: UInt16?
        let pageHideMask: UInt32?
        let bookmarkName: String?
        let indexmarkText: String?
        let rawPayload: [UInt8]
        let ctrlDataPayloads: [[UInt8]]
    }

    /// 표식을 문서 순서로 모은다. 표 셀·주석 본문은 걷지 않는다 — 실물에서
    /// 이 넷은 본문 문단에만 나오고, 재귀를 넓히면 이 축이 각주 축과 겹친다.
    static func sectionMarks(of file: HwpFile) -> [SectionMark] {
        file.sectionArray
            .flatMap(\.paragraph)
            .flatMap(sectionMarks(of:))
    }

    private static func sectionMarks(of paragraph: HwpParagraph) -> [SectionMark] {
        let controls = paragraph.ctrlHeaderArray ?? []
        var marks: [SectionMark] = []
        var extendedOrdinal = 0
        for char in paragraph.paraText?.charArray ?? [] where char.type == .extended {
            defer { extendedOrdinal += 1 }
            guard controls.indices.contains(extendedOrdinal),
                  let mark = sectionMark(of: controls[extendedOrdinal], code: char.value)
            else {
                continue
            }
            marks.append(mark)
        }
        return marks
    }

    /// 강등 상태도 축에 실어야 승격 전후가 갈린다 — `.notImplemented`는 4CC로
    /// 네 종류만 골라 담는다 (다른 미구현 컨트롤까지 실으면 이 축이 개체 축과
    /// 겹친다).
    private static func sectionMark(
        of ctrl: HwpCtrlId, code: UInt16
    ) -> SectionMark? {
        switch ctrl {
        case let .newNumber(control):
            sectionMark(
                kind: "newNumber", code: code, control: control,
                newNumberKind: control.newNumberInfo?.property,
                newNumberValue: control.newNumberInfo?.number
            )
        case let .pageHide(control):
            sectionMark(
                kind: "pageHide", code: code, control: control,
                pageHideMask: control.pageHideInfo?.rawValue
            )
        case let .bookmark(control):
            sectionMark(
                kind: "bookmark", code: code, control: control,
                bookmarkName: control.bookmarkInfo?.name
            )
        case let .indexmark(control):
            sectionMark(
                kind: "indexmark", code: code, control: control,
                indexmarkText: control.indexmarkInfo?.text,
                // 마지막 UINT32는 **저작기 버전 흔적**이다 — 한글 12.30이 -1을,
                // 레거시 문서 35건이 0을 쓴다. OWPML에 대응 속성이 없어 XML에서
                // 복원할 수 없으므로 매퍼가 최신 저작기 값을 고정하고, 이 축은
                // 그 4바이트만 0으로 접어 비교한다. 접지 않으면 레거시 저작
                // 쌍을 나중에 넣을 때 내용은 같은데 등식이 깨진다. 길이·키워드·
                // 두 번째 키워드 자리는 그대로 바이트 비교된다.
                normalizingTrailingWord: true
            )
        case let .notImplemented(header):
            demotedSectionMark(header: header, code: code)
        default:
            nil
        }
    }

    private static func sectionMark(
        kind: String,
        code: UInt16,
        control: HwpOtherControl,
        newNumberKind: UInt32? = nil,
        newNumberValue: UInt16? = nil,
        pageHideMask: UInt32? = nil,
        bookmarkName: String? = nil,
        indexmarkText: String? = nil,
        normalizingTrailingWord: Bool = false
    ) -> SectionMark {
        var payload = [UInt8](control.rawPayload)
        if normalizingTrailingWord, payload.count >= 4 {
            payload.replaceSubrange(payload.count - 4 ..< payload.count, with: [0, 0, 0, 0])
        }
        return SectionMark(
            kind: kind,
            controlCharacterCode: code,
            newNumberKind: newNumberKind,
            newNumberValue: newNumberValue,
            pageHideMask: pageHideMask,
            bookmarkName: bookmarkName,
            indexmarkText: indexmarkText,
            rawPayload: payload,
            ctrlDataPayloads: control.ctrlDataRecords.map { [UInt8]($0.rawPayload) }
        )
    }

    private static func demotedSectionMark(
        header: HwpCtrlHeader, code: UInt16
    ) -> SectionMark? {
        let demoted: Set<UInt32> = [
            HwpOtherCtrlId.newNumber.rawValue,
            HwpOtherCtrlId.pageHide.rawValue,
            HwpOtherCtrlId.bookmark.rawValue,
            HwpOtherCtrlId.indexmark.rawValue,
        ]
        guard demoted.contains(header.ctrlId) else {
            return nil
        }
        return SectionMark(
            kind: "notImplemented",
            controlCharacterCode: code,
            newNumberKind: nil,
            newNumberValue: nil,
            pageHideMask: nil,
            bookmarkName: nil,
            indexmarkText: nil,
            rawPayload: [UInt8](header.rawPayload),
            ctrlDataPayloads: []
        )
    }
}

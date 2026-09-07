@testable import CoreHwp
import Foundation

/// 각주·미주 등가 투영 (#168) — `DocumentEquivalenceProjection`의 각주 축.
///
/// 본체에서 떼어 둔 것은 파일·타입 길이 때문만이 아니다. 이 축은 기존 축들과
/// 달리 **컨트롤 안 리스트 문단**을 걷는다 — `printableText(of:)`·
/// `paragraphHeadings(of:)`의 재귀가 표 셀 한 갈래뿐이라 각주 본문을 보지
/// 못하므로, 같은 파일에 두면 두 종류의 순회 규약이 섞인다.
extension DocumentEquivalenceProjection {
    /// 각주·미주 하나 (#168) — 승격 전 HWPX는 컨트롤이 `.notImplemented`라
    /// 본문 텍스트가 모델에 아예 없었다. 번호 라벨은 각주 본문 문단 안
    /// `hp:autoNum`에서 나오므로 그 종류·모양·장식까지 축에 싣는다.
    /// `instId`는 축이 아니다 — 저장할 때마다 재부여되는 인스턴스 번호다.
    struct Note: Equatable {
        let isEndnote: Bool
        let text: String
        let autoNumberKind: UInt32?
        let autoNumberShape: Int?
        let autoNumberDecorations: [UInt16]?
    }

    /// 구역의 각주·미주 모양 (표 133·134, #168) — 조판이 읽는 값만 담는다.
    /// 구분선 값은 typed 저장 필드가 아니라 `dividerInfo`(rawPayload 재디코드)다.
    struct NoteShape: Equatable {
        let property: UInt32
        let startingNumber: UInt16
        let decorations: [UInt16]
        let dividerLength: Int32?
        let dividerMetrics: [Int16]
        let dividerType: UInt8
        let dividerThickness: UInt8
    }

    /// 각주·미주를 문서 순서로 모은다 (#168).
    static func notes(of file: HwpFile) -> [Note] {
        var notes: [Note] = []
        for section in file.sectionArray {
            for paragraph in section.paragraph {
                for ctrl in paragraph.ctrlHeaderArray ?? [] {
                    switch ctrl {
                    case let .footnote(control):
                        notes.append(note(of: control, isEndnote: false))
                    case let .endnote(control):
                        notes.append(note(of: control, isEndnote: true))
                    default:
                        continue
                    }
                }
            }
        }
        return notes
    }

    private static func note(of control: HwpListControl, isEndnote: Bool) -> Note {
        let paragraphs = control.listArray.flatMap(\.paragraphArray)
        var auto: HwpOtherControlAutoNumberInfo?
        for paragraph in paragraphs {
            for ctrl in paragraph.ctrlHeaderArray ?? [] {
                guard case let .autoNumber(control) = ctrl, auto == nil else { continue }
                auto = control.autoNumberInfo
            }
        }
        var text = ""
        for paragraph in paragraphs {
            for char in paragraph.paraText?.charArray ?? []
                where char.type == .char && char.value >= 32
            {
                text += String(decoding: [char.value], as: UTF16.self)
            }
        }
        return Note(
            isEndnote: isEndnote,
            text: text,
            autoNumberKind: auto?.kind.rawValue,
            autoNumberShape: auto?.numberShapeRawValue,
            autoNumberDecorations: auto.map {
                [$0.userSymbol, $0.decorationHead, $0.decorationTail]
            }
        )
    }

    /// 구역마다 각주·미주 모양을 순서대로 모은다 (#168).
    static func noteShapes(of file: HwpFile) -> [NoteShape] {
        file.sectionArray.flatMap { section -> [NoteShape] in
            guard let sectionDef = section.paragraph.first?.ctrlHeaderArray?
                .lazy.compactMap({ ctrl -> HwpSectionDef? in
                    guard case let .section(sectionDef) = ctrl else {
                        return nil
                    }
                    return sectionDef
                }).first
            else {
                return []
            }
            return [sectionDef.footNoteShape, sectionDef.endNoteShape].map { shape in
                let divider = shape.dividerInfo
                return NoteShape(
                    property: shape.property,
                    startingNumber: shape.startingNumber,
                    decorations: [
                        shape.userSymbolRawValue,
                        shape.decorationHeadRawValue,
                        shape.decorationTailRawValue,
                    ],
                    dividerLength: divider?.length,
                    dividerMetrics: [
                        divider?.marginTop ?? 0,
                        divider?.marginBottom ?? 0,
                        divider?.spacingBetweenNotes ?? 0,
                    ],
                    dividerType: divider?.type ?? 0,
                    dividerThickness: divider?.thickness ?? 0
                )
            }
        }
    }
}

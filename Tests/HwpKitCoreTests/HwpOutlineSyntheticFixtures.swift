@testable import CoreHwp
import Foundation
@testable import HwpKitCore

#if canImport(CoreText)
    /// 개요·책갈피 수집 (#77) 테스트용 합성 재료.
    ///
    /// `HwpSyntheticFixtures.swift`(이미 `file_length` 경고선 위)에 얹지 않고
    /// 여기 두는 것은 그 파일을 error 임계(700줄)로 밀지 않기 위해서다.
    extension HwpSynthetic {
        /// 문단 머리 모양 종류 = 1(개요) + 0-기반 수준 비트(표 44 bit 25-27).
        static func outlineParaShape(
            levelRawValue: UInt32,
            numberingOrBulletId: UInt16 = 0
        ) -> CoreHwp.HwpParaShape {
            CoreHwp.HwpParaShape(
                property1: (1 << 23) | (levelRawValue << 25),
                marginLeft: 0,
                tabDefId: 0,
                numberingOrBulletId: numberingOrBulletId
            )
        }

        /// 머리 모양이 개요가 **아닌** 문단 모양 — 스타일 이름 폴백을 태우는 쪽.
        /// raw `0x180`은 헌법주석의 `개요 8`·`개요 9` 스타일이 가리키는 실제 값이다.
        static func plainParaShape() -> CoreHwp.HwpParaShape {
            CoreHwp.HwpParaShape(property1: 0x180, marginLeft: 0, tabDefId: 0)
        }

        static func outlineStyle(_ localName: String, english: String = "") -> CoreHwp.HwpStyle {
            CoreHwp.HwpStyle(localName, english, nextId: 0, paraShapeId: 0, charShapeId: 0)
        }

        static func outlineIndex(
            paraShapes: [UInt32: CoreHwp.HwpParaShape] = [:],
            styles: [UInt32: CoreHwp.HwpStyle] = [:]
        ) -> HwpIndex {
            HwpIndex(
                charShapes: [:],
                paraShapes: paraShapes,
                borderFills: [:],
                tabDefs: [:],
                styles: styles,
                bullets: [:],
                numberings: [:],
                binData: [:],
                faceNamesKorean: [:],
                faceNamesEnglish: [:],
                faceNamesChinese: [:],
                faceNamesJapanese: [:],
                faceNamesEtc: [:],
                faceNamesSymbol: [:],
                faceNamesUser: [:]
            )
        }

        /// `HwpParaHeader`의 id 필드는 `let`이라 payload를 지어 loader로 만든다.
        static func outlineParaHeader(
            paraShapeId: UInt16,
            paraStyleId: UInt8
        ) throws -> CoreHwp.HwpParaHeader {
            var payload = Data()
            func append(_ value: some FixedWidthInteger) {
                withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
            }
            append(UInt32(0x8000_0000)) // isLastInList + charCount 0
            append(UInt32(0)) // controlMask
            append(paraShapeId)
            append(paraStyleId)
            append(UInt8(0)) // columnType
            append(UInt16(1)) // charShapeInfoCount
            append(UInt16(0)) // rangeTagInfoCount
            append(UInt16(1)) // alignInfoCount
            append(UInt32(0)) // paraId
            append(UInt16(0)) // isTraceChange (5.0.3.2+)
            return try CoreHwp.HwpParaHeader.load(payload, CoreHwp.HwpVersion(5, 0, 3, 2))
        }

        /// 문단 모양·스타일 id를 지정한 한 줄 문단.
        static func styledParagraph(
            _ text: String,
            paraShapeId: UInt16 = 0,
            paraStyleId: UInt8 = 0
        ) throws -> CoreHwp.HwpParagraph {
            var paragraph = try textParagraph(text)
            paragraph.paraHeader = try outlineParaHeader(
                paraShapeId: paraShapeId, paraStyleId: paraStyleId
            )
            return paragraph
        }

        /// 이름 있는 책갈피 컨트롤 (이름이 nil이면 `bookmarkInfo` 자체가 없다).
        static func bookmarkControl(_ name: String?) -> CoreHwp.HwpCtrlId {
            .bookmark(CoreHwp.HwpOtherControl(
                ctrlId: .bookmark,
                rawTrailing: Data(),
                rawPayload: Data(),
                ctrlDataRecords: [],
                unknownChildren: [],
                bookmarkInfo: name.map { name in
                    CoreHwp.HwpOtherControlBookmarkInfo(
                        nameCharacterCount: name.utf16.count,
                        nameLengthRawPayload: Data(),
                        name: name,
                        nameRawPayload: Data(),
                        rawTrailing: Data()
                    )
                }
            ))
        }

        static func outlinePaginator(
            bodyParagraphs: [CoreHwp.HwpParagraph],
            index: HwpIndex,
            pageHeight: UInt32 = 84188
        ) -> HwpPaginator {
            let section = section(
                firstParagraphControls: [.section(sectionDef(pageHeight: pageHeight))],
                bodyParagraphs: bodyParagraphs
            )
            return HwpPaginator(
                sections: [section],
                index: index,
                fontResolver: .testDeterministic
            )
        }
    }
#endif

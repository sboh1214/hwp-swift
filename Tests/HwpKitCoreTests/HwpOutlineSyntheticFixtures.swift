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

        /// 문단 머리 모양 종류 = 2(번호 매기기) + 0-기반 수준 비트 — 정의 참조는
        /// 개요와 달리 문단 모양 자신의 `numberingOrBulletId`(1-based)다 (#152).
        static func numberingParaShape(
            levelRawValue: UInt32,
            numberingOrBulletId: UInt16
        ) -> CoreHwp.HwpParaShape {
            CoreHwp.HwpParaShape(
                property1: (2 << 23) | (levelRawValue << 25),
                marginLeft: 0,
                tabDefId: 0,
                numberingOrBulletId: numberingOrBulletId
            )
        }

        /// 수준 1-7의 형식을 가진 합성 번호 정의 — 문단 머리 정보는 빈 문서
        /// 기본값(`^1.` 0x0C 꼴)에 수준별 번호 모양(표 41, 기본 숫자)만 얹은 12바이트다.
        /// 시작 번호 방식은 기본 새 번호(1) — 이어 매기기(0)는 인자로 준다 (#153).
        static func numberingDefinition(
            formats: [String] = ["^1.", "^2.", "^3.", "(^4)", "(^5)", "^6)", "^7)"],
            numberFormats: [Int] = [],
            startingIndex: UInt16 = 1,
            startingIndexArray: [UInt32]? = nil,
            extendedFormats: [String]? = nil,
            extendedNumberFormats: [Int] = [],
            extendedStartingIndexArray: [UInt32]? = nil
        ) -> CoreHwp.HwpNumbering {
            func format(_ format: String, shape: Int) -> CoreHwp.HwpNumberingFormat {
                CoreHwp.HwpNumberingFormat(
                    property: CoreHwp.HwpParaHeadInfo(
                        alignment: .left, useInstWidth: true, autoIndent: true,
                        textOffsetType: .percent, numberFormat: shape, textOffset: 50
                    ).bytes,
                    formatLength: WORD(format.utf16.count),
                    format: format
                )
            }
            return CoreHwp.HwpNumbering(
                formatArray: formats.enumerated().map { offset, text in
                    format(
                        text,
                        shape: numberFormats.indices.contains(offset) ? numberFormats[offset] : 0
                    )
                },
                startingIndex: startingIndex,
                startingIndexArray: startingIndexArray,
                extendedFormatArray: extendedFormats?.enumerated().map { offset, text in
                    format(
                        text,
                        shape: extendedNumberFormats.indices.contains(offset)
                            ? extendedNumberFormats[offset] : 0
                    )
                },
                extendedStartingIndexArray: extendedStartingIndexArray
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
            styles: [UInt32: CoreHwp.HwpStyle] = [:],
            numberings: [UInt32: CoreHwp.HwpNumbering] = [:]
        ) -> HwpIndex {
            HwpIndex(
                charShapes: [:],
                paraShapes: paraShapes,
                borderFills: [:],
                tabDefs: [:],
                styles: styles,
                bullets: [:],
                numberings: numberings,
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
            pageHeight: UInt32 = 84188,
            outlineNumberingId: UInt16 = 1
        ) -> HwpPaginator {
            let section = section(
                firstParagraphControls: [.section(sectionDef(
                    pageHeight: pageHeight, outlineNumberingId: outlineNumberingId
                ))],
                bodyParagraphs: bodyParagraphs
            )
            return HwpPaginator(
                sections: [section],
                index: index,
                fontResolver: .testDeterministic
            )
        }
    }

    // MARK: - 문단 번호·개요 번호 생성 (#153)

    extension HwpSynthetic {
        /// 번호 생성 테스트의 문단 모양 사전 — id 1-7은 개요 1-7수준, `d`×10 + 1-8은
        /// 정의 `d`(1-3)를 가리키는 번호 매기기 1-8수준, 8은 글머리표, 9는 본문.
        static func numberingIndex(
            numberings: [UInt32: CoreHwp.HwpNumbering]
        ) -> HwpIndex {
            var shapes: [UInt32: CoreHwp.HwpParaShape] = [:]
            for level in UInt32(0) ... 6 {
                shapes[level + 1] = outlineParaShape(levelRawValue: level)
            }
            for definition in UInt32(1) ... 3 {
                for level in UInt32(0) ... 7 {
                    shapes[definition * 10 + level + 1] = numberingParaShape(
                        levelRawValue: level, numberingOrBulletId: UInt16(definition)
                    )
                }
            }
            shapes[8] = CoreHwp.HwpParaShape(
                property1: 3 << 23, marginLeft: 0, tabDefId: 0, numberingOrBulletId: 1
            )
            shapes[9] = plainParaShape()
            return outlineIndex(paraShapes: shapes, numberings: numberings)
        }

        /// 구역 정의 하나 뒤에 문단을 잇는 구역 — 개요 정의 참조는 인자로.
        static func numberingSection(
            outlineNumberingId: UInt16 = 1,
            paragraphs: [CoreHwp.HwpParagraph]
        ) -> CoreHwp.HwpSection {
            section(
                firstParagraphControls: [
                    .section(sectionDef(outlineNumberingId: outlineNumberingId)),
                ],
                bodyParagraphs: paragraphs
            )
        }

        /// 한 구역 문서의 번호 표.
        static func generateNumbering(
            _ paragraphs: [CoreHwp.HwpParagraph],
            numberings: [UInt32: CoreHwp.HwpNumbering],
            outlineNumberingId: UInt16 = 1
        ) -> HwpParagraphNumbering {
            HwpParagraphNumbering.generate(
                sections: [numberingSection(
                    outlineNumberingId: outlineNumberingId, paragraphs: paragraphs
                )],
                index: numberingIndex(numberings: numberings)
            )
        }
    }
#endif

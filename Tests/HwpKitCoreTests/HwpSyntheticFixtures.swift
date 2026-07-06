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
        // 빈 문서 템플릿의 라인 캐시(10pt)가 CT 레이아웃 높이를 덮어쓰지 않게 비운다.
        paragraph.paraLineSeg.paraLineSegInternalArray = []
        return paragraph
    }

    /// 라인 세그먼트 캐시가 있는 문단 (단위: HWPUNIT).
    /// 일부 저장본 (한/글 2007 계열)처럼 lineLocation을 페이지 내 절대 y로 준
    /// 케이스와 문단-상대 (0 시작) 케이스를 모두 만들 수 있다.
    static func lineSegParagraph(
        _ text: String,
        segments: [(location: Int32, height: Int32)]
    ) throws -> CoreHwp.HwpParagraph {
        var paragraph = try textParagraph(text)
        var payload = Data()
        for segment in segments {
            withUnsafeBytes(of: UInt32(0).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: segment.location.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: segment.height.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: segment.height.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int32(850).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int32(600).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int32(0).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int32(42520).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(393_216).littleEndian) { payload.append(contentsOf: $0) }
        }
        paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
        return paragraph
    }

    /// columnCacheParagraph 세그먼트 사양
    struct ColumnCacheSegment {
        let textIndex: UInt32
        let location: Int32
        let height: Int32
        let width: Int32

        init(textIndex: UInt32, location: Int32, height: Int32, width: Int32) {
            self.textIndex = textIndex
            self.location = location
            self.height = height
            self.width = width
        }
    }

    /// 라인 세그먼트 캐시 (textStartingIndex/width까지 지정): 단 경계
    /// (loc 리셋 + width 변화)를 담은 다단 배분 캐시를 만든다.
    /// paraHeader.charCount도 텍스트 길이로 채운다 (단 배분의 비례 환산 분모).
    static func columnCacheParagraph(
        _ text: String,
        segments: [ColumnCacheSegment]
    ) throws -> CoreHwp.HwpParagraph {
        var paragraph = try textParagraph(text)
        var payload = Data()
        for segment in segments {
            withUnsafeBytes(of: segment.textIndex.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: segment.location.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: segment.height.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: segment.height.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int32(850).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int32(600).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: Int32(0).littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: segment.width.littleEndian) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(393_216).littleEndian) { payload.append(contentsOf: $0) }
        }
        paragraph.paraLineSeg = try CoreHwp.HwpParaLineSeg.load(payload)
        var headerPayload = Data()
        withUnsafeBytes(of: UInt32(text.utf16.count).littleEndian) {
            headerPayload.append(contentsOf: $0)
        }
        withUnsafeBytes(of: UInt32(0).littleEndian) { headerPayload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { headerPayload.append(contentsOf: $0) }
        headerPayload.append(0) // paraStyleId
        headerPayload.append(0) // columnType
        withUnsafeBytes(of: UInt16(1).littleEndian) { headerPayload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { headerPayload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { headerPayload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(0).littleEndian) { headerPayload.append(contentsOf: $0) }
        paragraph.paraHeader = try CoreHwp.HwpParaHeader.load(
            headerPayload,
            CoreHwp.HwpVersion(5, 0, 2, 2)
        )
        return paragraph
    }

    /// 단 정의 컨트롤 (표 138/139 없이 모델 직접 구성)
    static func column(
        count: Int,
        spacing: Int16? = nil,
        widths: [UInt16]? = nil,
        gaps: [UInt16]? = nil
    ) -> CoreHwp.HwpColumn {
        var column = CoreHwp.HwpColumn()
        column.property = CoreHwp.HwpColumnProperty(
            rawValue: 0,
            type: .general,
            count: count,
            direction: .left,
            isSameWidth: widths == nil
        )
        column.spacing = spacing
        column.widthArray = widths
        column.gapArray = gaps
        return column
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

    /// 페이지 크기를 지정한 구역 정의 (단위: HWPUNIT).
    /// 머리말/꼬리말 여백은 본문 밖 예약 영역이라 본문 높이를 줄인다
    /// (HwpPageGeometry, 표 137) — 합성 테스트는 본문 높이 산정이 단순하도록
    /// 0으로 둔다 (본문 = 페이지 높이 − 위/아래 여백).
    static func sectionDef(
        pageWidth: UInt32 = 59528,
        pageHeight: UInt32 = 84188
    ) -> CoreHwp.HwpSectionDef {
        var sectionDef = CoreHwp.HwpSectionDef()
        sectionDef.pageDef.width = pageWidth
        sectionDef.pageDef.height = pageHeight
        sectionDef.pageDef.marginHeader = 0
        sectionDef.pageDef.marginFootnote = 0
        return sectionDef
    }

    /// 앞/뒤 텍스트 사이에 extended 컨트롤 문자(코드 11)가 있는 문단
    static func paragraphWithInlineControl(
        prefix: String,
        suffix: String
    ) -> CoreHwp.HwpParagraph {
        var paragraph = CoreHwp.HwpParagraph()
        var paraText = CoreHwp.HwpParaText()
        paraText.charArray = prefix.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
            + [CoreHwp.HwpChar(type: .extended, value: 11)]
            + suffix.utf16.map { CoreHwp.HwpChar(type: .char, value: $0) }
        paragraph.paraText = paraText
        paragraph.paraLineSeg.paraLineSegInternalArray = []
        return paragraph
    }

    /// 쪽 나누기 (문단 헤더 columnType bit 2)로 시작하는 문단
    static func pageBreakParagraph(_ text: String) throws -> CoreHwp.HwpParagraph {
        var paragraph = try textParagraph(text)
        var payload = Data()
        let charCount = UInt32(0x8000_0000) | UInt32(text.utf16.count)
        withUnsafeBytes(of: charCount.littleEndian) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(0).littleEndian) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { payload.append(contentsOf: $0) }
        payload.append(0) // paraStyleId
        payload.append(0b100) // columnType: 쪽 나누기
        withUnsafeBytes(of: UInt16(1).littleEndian) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(0).littleEndian) { payload.append(contentsOf: $0) }
        paragraph.paraHeader = try CoreHwp.HwpParaHeader.load(
            payload,
            CoreHwp.HwpVersion(5, 0, 2, 2)
        )
        return paragraph
    }

    /// 글자처럼 취급 (treatAsChar) gso 개체.
    /// 빈 shape component 하나 → 크기 bounding box 도형으로 렌더된다.
    static func inlineShapeObject(
        width: UInt32,
        height: UInt32,
        instanceId: UInt32 = 0
    ) -> CoreHwp.HwpGenShapeObject {
        var common = CoreHwp.HwpCommonCtrlProperty(commonCtrlId: .genShapeObject)
        common.width = width
        common.height = height
        common.instanceId = instanceId
        var info = CoreHwp.HwpCommonCtrlPropertyInfo()
        info.treatAsChar = true
        common.propertyInfo = info
        return CoreHwp.HwpGenShapeObject(
            commonCtrlProperty: common,
            rawPayload: Data(),
            rawTrailing: Data(),
            shapeComponentArray: [CoreHwp.HwpShapeComponent(
                rawCtrlId: nil,
                ctrlId: nil,
                rawPayload: Data(),
                rawTrailing: nil,
                pictureArray: [],
                oleArray: [],
                oleRecords: [],
                ctrlDataRecords: [],
                textBoxListArray: [],
                unknownChildren: []
            )],
            ctrlDataRecords: [],
            unknownChildren: []
        )
    }

    /// 셀 하나 (주소/크기 지정, 단위: HWPUNIT)
    static func tableCell(
        row: Int,
        column: Int,
        width: UInt32,
        height: UInt32,
        paragraphs: [CoreHwp.HwpParagraph],
        isHeader: Bool = false
    ) -> CoreHwp.HwpTableCell {
        CoreHwp.HwpTableCell(
            header: CoreHwp.HwpTableCellHeader(
                paragraphCount: Int32(paragraphs.count),
                property: 0,
                propertyInfo: CoreHwp.HwpListHeaderProperty(),
                listHeaderWidthRef: isHeader ? 1 << 2 : 0,
                cellPropertyInfo: CoreHwp.HwpTableCellHeaderProperty(
                    rawValue: isHeader ? 1 << 2 : 0
                ),
                isHeader: isHeader,
                cellProperty: CoreHwp.HwpTableCellProperty(
                    columnAddress: UInt16(column),
                    rowAddress: UInt16(row),
                    width: width,
                    height: height
                ),
                rawTrailing: Data(),
                rawPayload: Data(),
                unknownChildren: []
            ),
            paragraphArray: paragraphs
        )
    }

    /// 표 컨트롤. cellParagraphs는 [행][열] 순서의 문단 배열.
    /// property는 표 76 속성 u32 (bits 0-1 = 쪽 경계 나눔: 0 없음, 2 나눔;
    /// bit 2 = 제목 줄 자동 반복). headerRowCount는 앞에서부터 제목 셀로 표시할 행 수.
    static func table(
        cellWidth: UInt32,
        rowHeights: [UInt32],
        property: UInt32 = 2,
        headerRowCount: Int = 0,
        cellParagraphs: [[[CoreHwp.HwpParagraph]]]
    ) -> CoreHwp.HwpTable {
        let rowCount = cellParagraphs.count
        let columnCount = cellParagraphs.first?.count ?? 0
        var rowSize = Data()
        for _ in 0 ..< rowCount {
            withUnsafeBytes(of: UInt16(columnCount).littleEndian) {
                rowSize.append(contentsOf: $0)
            }
        }
        var cells: [CoreHwp.HwpTableCell] = []
        for (rowIndex, columns) in cellParagraphs.enumerated() {
            for (columnIndex, paragraphs) in columns.enumerated() {
                cells.append(tableCell(
                    row: rowIndex,
                    column: columnIndex,
                    width: cellWidth,
                    height: rowHeights[rowIndex],
                    paragraphs: paragraphs,
                    isHeader: rowIndex < headerRowCount
                ))
            }
        }
        return CoreHwp.HwpTable(
            property: CoreHwp.HwpTableProperty(
                property: property,
                rowCount: UInt16(rowCount),
                columnCount: UInt16(columnCount),
                cellSpacing: 0,
                leftInnerMargin: 0,
                rightInnerMargin: 0,
                topInnerMargin: 0,
                bottomInnerMargin: 0,
                rowSize: [UInt8](rowSize),
                borderFillId: 0,
                validZoneInfoSize: nil,
                zonePropertyArray: nil,
                rawPayload: Data(),
                rawTrailing: Data()
            ),
            cellArray: cells
        )
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

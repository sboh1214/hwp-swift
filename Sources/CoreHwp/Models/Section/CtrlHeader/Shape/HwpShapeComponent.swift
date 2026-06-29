import Foundation

// swiftlint:disable file_length

/** 개체 요소 세부 raw record */
public struct HwpShapeComponentRawRecord {
    /** 원본 payload */
    public var rawPayload: Data
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpShapeComponentRawRecord: HwpPrimitive {
    // MARK: loader contract exemption - raw shape-component record keeps entire payload

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}

protocol HwpShapeComponentRawRecordBacked: HwpFromRecord {
    static var expectedSectionTag: HwpSectionTag { get }

    init(rawPayload: Data, unknownChildren: [HwpUnknownRecord])
}

extension HwpShapeComponentRawRecordBacked {
    // MARK: loader contract exemption - raw-backed shape records keep entire payload

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        self.init(
            rawPayload: try reader.readToEnd(),
            unknownChildren: children.map(HwpUnknownRecord.init)
        )
    }

    // MARK: loader contract exemption - validates shape record tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: expectedSectionTag)

        var reader = DataReader(record.payload)
        let rawRecord = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return rawRecord
    }
}

/** 선 개체 요소 세부 record */
public struct HwpShapeComponentLine: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .shapeComponentLine
}

/** 타원 개체 요소 세부 record */
public struct HwpShapeComponentEllipse: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .shapeComponentEllipse
}

/** 호 개체 요소 세부 record */
public struct HwpShapeComponentArc: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .shapeComponentArc
}

/** 다각형 개체 요소 세부 record */
public struct HwpShapeComponentPolygon: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .shapeComponentPolygon
}

/** 곡선 개체 요소 세부 record */
public struct HwpShapeComponentCurve: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .shapeComponentCurve
}

/** 컨테이너 개체 요소 세부 record */
public struct HwpShapeComponentContainer: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .shapeComponentContainer
}

/** 차트 데이터 record */
public struct HwpShapeComponentChartData: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .chartData
}

/** 글맵시 개체 요소 세부 record */
public struct HwpShapeComponentTextart: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .shapeComponentTextart
}

/** 양식 개체 record */
public struct HwpShapeComponentFormObject: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .formObject
}

/** 메모 모양 record */
public struct HwpShapeComponentMemoShape: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .memoShape
}

/** 메모 목록 record */
public struct HwpShapeComponentMemoList: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .memoList
}

/** 동영상 데이터 record */
public struct HwpShapeComponentVideoData: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .videoData
}

/** 아직 세부 타입이 확정되지 않은 개체 요소 세부 record */
public struct HwpShapeComponentUnknown: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedSectionTag: HwpSectionTag = .shapeComponentUnknown
}

/** 개체 요소 공통 레코드 */
public struct HwpShapeComponent {
    /** 원본 ctrl id */
    public var rawCtrlId: UInt32?
    /** ctrl id */
    public var ctrlId: HwpCommonCtrlId?
    /** ctrl id 이름 */
    public var ctrlIdName: String = "unknown"
    /** 원본 payload */
    public var rawPayload: Data
    /** ctrl id 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data?
    /** 그림 개체 요소 */
    public var pictureArray: [HwpShapeComponentPicture]
    /** 선 개체 요소 세부 record */
    public var lineArray: [HwpShapeComponentLine] = []
    /** 사각형 개체 요소 세부 record */
    public var rectangleArray: [HwpShapeComponentRectangle] = []
    /** 타원 개체 요소 세부 record */
    public var ellipseArray: [HwpShapeComponentEllipse] = []
    /** 호 개체 요소 세부 record */
    public var arcArray: [HwpShapeComponentArc] = []
    /** 다각형 개체 요소 세부 record */
    public var polygonArray: [HwpShapeComponentPolygon] = []
    /** 곡선 개체 요소 세부 record */
    public var curveArray: [HwpShapeComponentCurve] = []
    /** OLE 개체 요소 */
    public var oleArray: [HwpShapeComponentOLE]
    /** OLE 개체 요소 raw record */
    public var oleRecords: [HwpUnknownRecord]
    /** 컨테이너 개체 요소 세부 record */
    public var containerArray: [HwpShapeComponentContainer] = []
    /** 차트 데이터 record */
    public var chartDataArray: [HwpShapeComponentChartData] = []
    /** 글맵시 개체 요소 세부 record */
    public var textartArray: [HwpShapeComponentTextart] = []
    /** 양식 개체 record */
    public var formObjectArray: [HwpShapeComponentFormObject] = []
    /** 메모 모양 record */
    public var memoShapeArray: [HwpShapeComponentMemoShape] = []
    /** 메모 목록 record */
    public var memoListArray: [HwpShapeComponentMemoList] = []
    /** 동영상 데이터 record */
    public var videoDataArray: [HwpShapeComponentVideoData] = []
    /** 아직 세부 타입이 확정되지 않은 개체 요소 세부 record */
    public var shapeComponentUnknownArray: [HwpShapeComponentUnknown] = []
    /** 컨트롤 데이터 child record */
    public var ctrlDataRecords: [HwpCtrlData]
    /** 글상자 내부 리스트와 문단 */
    public var textBoxListArray: [HwpListControlList] = []
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpShapeComponent: HwpFromRecord {
    // MARK: loader contract exemption - preserves common shape-component payload as raw data

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        rawCtrlId = Self.rawCtrlId(from: rawPayload)
        ctrlId = rawCtrlId.flatMap(HwpCommonCtrlId.init(rawValue:))
        ctrlIdName = ctrlId.map(String.init(describing:)) ?? "unknown"
        rawTrailing = Self.rawTrailing(from: rawPayload)
        pictureArray = try children
            .filter { $0.tagId == HwpSectionTag.shapeComponentPicture.rawValue }
            .map { try HwpShapeComponentPicture.load($0) }
        lineArray = try Self.records(from: children, tagged: .shapeComponentLine)
        rectangleArray = try children
            .filter { $0.tagId == HwpSectionTag.shapeComponentRectangle.rawValue }
            .map { try HwpShapeComponentRectangle.load($0) }
        ellipseArray = try Self.records(from: children, tagged: .shapeComponentEllipse)
        arcArray = try Self.records(from: children, tagged: .shapeComponentArc)
        polygonArray = try Self.records(from: children, tagged: .shapeComponentPolygon)
        curveArray = try Self.records(from: children, tagged: .shapeComponentCurve)
        oleArray = try children
            .filter { $0.tagId == HwpSectionTag.shapeComponentOle.rawValue }
            .map { try HwpShapeComponentOLE.load($0) }
        oleRecords = children
            .filter { $0.tagId == HwpSectionTag.shapeComponentOle.rawValue }
            .map(HwpUnknownRecord.init)
        containerArray = try Self.records(from: children, tagged: .shapeComponentContainer)
        chartDataArray = try Self.records(from: children, tagged: .chartData)
        textartArray = try Self.records(from: children, tagged: .shapeComponentTextart)
        formObjectArray = try Self.records(from: children, tagged: .formObject)
        memoShapeArray = try Self.records(from: children, tagged: .memoShape)
        memoListArray = try Self.records(from: children, tagged: .memoList)
        videoDataArray = try Self.records(from: children, tagged: .videoData)
        shapeComponentUnknownArray = try Self.records(
            from: children,
            tagged: .shapeComponentUnknown
        )
        ctrlDataRecords = try children
            .filter { $0.tagId == HwpSectionTag.ctrlData.rawValue }
            .map { try HwpCtrlData.load($0) }
        textBoxListArray = []
        unknownChildren = children
            .filter { !Self.consumedChildTagIds.contains($0.tagId) }
            .map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - parses nested text-box lists after raw preservation

    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        var component = try load(record)
        let parsedTextBox = try parseTextBoxLists(record.children, version)
        component.textBoxListArray = parsedTextBox.lists
        component.unknownChildren = record.children
            .enumerated()
            .filter { index, child in
                !parsedTextBox.consumedIndexes.contains(index)
                    && !Self.consumedChildTagIds.contains(child.tagId)
            }
            .map { HwpUnknownRecord($0.element) }
        return component
    }

    // MARK: loader contract exemption - validates shape-component tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .shapeComponent)

        var reader = DataReader(record.payload)
        let component = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return component
    }

    private static func records<Record: HwpFromRecord>(
        from children: [HwpRecord],
        tagged tag: HwpSectionTag
    ) throws -> [Record] {
        try children
            .filter { $0.tagId == tag.rawValue }
            .map { try Record.load($0) }
    }

    private static var consumedChildTagIds: Set<UInt32> {
        [
            HwpSectionTag.shapeComponentLine.rawValue,
            HwpSectionTag.shapeComponentRectangle.rawValue,
            HwpSectionTag.shapeComponentEllipse.rawValue,
            HwpSectionTag.shapeComponentArc.rawValue,
            HwpSectionTag.shapeComponentPolygon.rawValue,
            HwpSectionTag.shapeComponentCurve.rawValue,
            HwpSectionTag.shapeComponentOle.rawValue,
            HwpSectionTag.shapeComponentPicture.rawValue,
            HwpSectionTag.shapeComponentContainer.rawValue,
            HwpSectionTag.chartData.rawValue,
            HwpSectionTag.shapeComponentTextart.rawValue,
            HwpSectionTag.formObject.rawValue,
            HwpSectionTag.memoShape.rawValue,
            HwpSectionTag.memoList.rawValue,
            HwpSectionTag.videoData.rawValue,
            HwpSectionTag.shapeComponentUnknown.rawValue,
            HwpSectionTag.ctrlData.rawValue,
        ]
    }

    private static func rawCtrlId(from payload: Data) -> UInt32? {
        guard payload.count >= MemoryLayout<UInt32>.size else {
            return nil
        }
        do {
            return try payload.readLittleEndianUInt32(at: 0)
        } catch {
            return nil
        }
    }

    private static func rawTrailing(from payload: Data) -> Data? {
        guard payload.count >= MemoryLayout<UInt32>.size else {
            return nil
        }
        return Data(payload.dropFirst(MemoryLayout<UInt32>.size))
    }

    private static func parseTextBoxLists(
        _ children: [HwpRecord],
        _ version: HwpVersion
    ) throws -> (lists: [HwpListControlList], consumedIndexes: Set<Int>) {
        var lists = [HwpListControlList]()
        var consumedIndexes = Set<Int>()
        var index = 0

        while index < children.count {
            let child = children[index]
            guard child.tagId == HwpSectionTag.listHeader.rawValue else {
                index += 1
                continue
            }

            let header = try HwpListHeader.load(child.payload)
            guard header.paragraphCount >= 0 else {
                throw HwpError.invalidRecordTree(
                    reason: "text box paragraph count is negative: \(header.paragraphCount)"
                )
            }

            let startIndex = index
            var paragraphs = [HwpParagraph]()
            for _ in 0 ..< Int(header.paragraphCount) {
                index += 1
                guard index < children.count else {
                    throw HwpError.invalidRecordTree(reason: "text box paragraph is missing")
                }
                let paragraphRecord = children[index]
                guard paragraphRecord.tagId == HwpSectionTag.paraHeader.rawValue else {
                    throw HwpError.invalidRecordTree(
                        reason: "text box expected paragraph, got tag \(paragraphRecord.tagId)"
                    )
                }
                paragraphs.append(try HwpParagraph.load(paragraphRecord, version))
            }

            lists.append(HwpListControlList(
                header: header,
                headerRawPayload: child.payload,
                headerUnknownChildren: child.children.map(HwpUnknownRecord.init),
                paragraphArray: paragraphs
            ))
            consumedIndexes.formUnion(startIndex ... index)
            index += 1
        }

        return (lists, consumedIndexes)
    }
}

/** 사각형 개체 요소 */
public struct HwpShapeComponentRectangle {
    /** 원본 payload */
    public var rawPayload: Data
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpShapeComponentRectangle: HwpFromRecord {
    // MARK: loader contract exemption - rectangle component payload is raw-backed

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates rectangle component tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .shapeComponentRectangle)

        var reader = DataReader(record.payload)
        let rectangle = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return rectangle
    }
}

/** OLE 개체 요소 */
public struct HwpShapeComponentOLE {
    /** 원본 payload */
    public var rawPayload: Data
    /** BinData id. 아직 전체 payload layout을 해석하지 않았으므로 없을 수 있다. */
    public var binaryDataId: UInt32?
    /** BinData id 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data?
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpShapeComponentOLE: HwpFromRecord {
    // MARK: loader contract exemption - OLE component payload is best-effort raw-backed

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        binaryDataId = Self.binaryDataId(from: rawPayload)
        rawTrailing = Self.rawTrailing(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates OLE component tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .shapeComponentOle)

        var reader = DataReader(record.payload)
        let ole = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return ole
    }

    private static func binaryDataId(from payload: Data) -> UInt32? {
        guard payload.count >= MemoryLayout<UInt32>.size else {
            return nil
        }
        do {
            return try payload.readLittleEndianUInt32(at: 0)
        } catch {
            return nil
        }
    }

    private static func rawTrailing(from payload: Data) -> Data? {
        guard payload.count >= MemoryLayout<UInt32>.size else {
            return nil
        }
        return Data(payload.dropFirst(MemoryLayout<UInt32>.size))
    }
}

/** 그림 개체 요소 */
public struct HwpShapeComponentPicture {
    /** 원본 payload */
    public var rawPayload: Data
    /** BinData id. 아직 전체 payload layout을 해석하지 않았으므로 없을 수 있다. */
    public var binaryDataId: UInt16?
    /** BinData id 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data?
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpShapeComponentPicture: HwpFromRecord {
    // MARK: loader contract exemption - picture component payload is best-effort raw-backed

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        rawPayload = try reader.readToEnd()
        binaryDataId = Self.binaryDataId(from: rawPayload)
        rawTrailing = Self.rawTrailing(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    // MARK: loader contract exemption - validates picture component tag before raw preservation

    static func load(_ record: HwpRecord) throws -> Self {
        try validateSectionRecordTag(record, expectedTag: .shapeComponentPicture)

        var reader = DataReader(record.payload)
        let picture = try self.init(&reader, record.children)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return picture
    }

    private static func binaryDataId(from payload: Data) -> UInt16? {
        let offset = 71
        guard payload.count >= offset + MemoryLayout<UInt16>.size else {
            return nil
        }
        do {
            return try payload.readLittleEndianUInt16(at: offset)
        } catch {
            return nil
        }
    }

    private static func rawTrailing(from payload: Data) -> Data? {
        let offset = 71 + MemoryLayout<UInt16>.size
        guard payload.count >= offset else {
            return nil
        }
        return Data(payload.dropFirst(offset))
    }
}

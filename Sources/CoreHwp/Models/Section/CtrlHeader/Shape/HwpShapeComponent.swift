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
        // 세부 디코딩 접근자가 load 반환 후 rawPayload를 다시 읽으므로
        // 보존 off에서도 비우지 않고 분리 복사한다 (개체 payload는 소량).
        rawPayload = reader.options.decoupledPayload(try reader.readToEnd())
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}

protocol HwpShapeComponentRawRecordBacked: HwpTagValidatedRecord
    where ExpectedTag == HwpSectionTag
{
    init(rawPayload: Data, unknownChildren: [HwpUnknownRecord])
}

extension HwpShapeComponentRawRecordBacked {
    // MARK: loader contract exemption - raw-backed shape records keep entire payload

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        // xxxDetail 디코딩 접근자가 load 반환 후 rawPayload를 다시 읽으므로
        // 보존 off에서도 비우지 않고 분리 복사한다 (개체 payload는 소량).
        self.init(
            rawPayload: reader.options.decoupledPayload(try reader.readToEnd()),
            unknownChildren: children.map(HwpUnknownRecord.init)
        )
    }
}

/** 선 개체 요소 세부 record */
public struct HwpShapeComponentLine: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .shapeComponentLine
}

/** 타원 개체 요소 세부 record */
public struct HwpShapeComponentEllipse: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .shapeComponentEllipse
}

/** 호 개체 요소 세부 record */
public struct HwpShapeComponentArc: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .shapeComponentArc
}

/** 다각형 개체 요소 세부 record */
public struct HwpShapeComponentPolygon: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .shapeComponentPolygon
}

/** 곡선 개체 요소 세부 record */
public struct HwpShapeComponentCurve: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .shapeComponentCurve
}

/** 컨테이너 개체 요소 세부 record */
public struct HwpShapeComponentContainer: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .shapeComponentContainer
}

/** 차트 데이터 record */
public struct HwpShapeComponentChartData: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .chartData
}

/** 글맵시 개체 요소 세부 record */
public struct HwpShapeComponentTextart: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .shapeComponentTextart
}

/** 양식 개체 record */
public struct HwpShapeComponentFormObject: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .formObject
}

/** 메모 모양 record */
public struct HwpShapeComponentMemoShape: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .memoShape
}

/** 메모 목록 record */
public struct HwpShapeComponentMemoList: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .memoList
}

/** 동영상 데이터 record */
public struct HwpShapeComponentVideoData: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .videoData
}

/** 아직 세부 타입이 확정되지 않은 개체 요소 세부 record */
public struct HwpShapeComponentUnknown: HwpShapeComponentRawRecordBacked {
    public var rawPayload: Data
    public var unknownChildren: [HwpUnknownRecord]

    static let expectedTag: HwpSectionTag = .shapeComponentUnknown
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

extension HwpShapeComponent {
    private enum DecodingKeys: String, CodingKey {
        case rawCtrlId, ctrlId, ctrlIdName, rawPayload, rawTrailing
        case pictureArray, lineArray, rectangleArray, ellipseArray, arcArray
        case polygonArray, curveArray, oleArray, oleRecords, containerArray
        case chartDataArray, textartArray, formObjectArray, memoShapeArray
        case memoListArray, videoDataArray, shapeComponentUnknownArray
        case ctrlDataRecords, textBoxListArray, unknownChildren
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        rawCtrlId = try container.decodeIfPresent(UInt32.self, forKey: .rawCtrlId)
        ctrlId = try container.decodeIfPresent(HwpCommonCtrlId.self, forKey: .ctrlId)
        ctrlIdName = try container.decode(String.self, forKey: .ctrlIdName)
        rawPayload = try container.decode(Data.self, forKey: .rawPayload)
        rawTrailing = try container.decodeIfPresent(Data.self, forKey: .rawTrailing)
        pictureArray = try container.decode(
            [HwpShapeComponentPicture].self, forKey: .pictureArray
        )
        lineArray = try container.decode([HwpShapeComponentLine].self, forKey: .lineArray)
        rectangleArray = try container.decode(
            [HwpShapeComponentRectangle].self, forKey: .rectangleArray
        )
        ellipseArray = try container.decode(
            [HwpShapeComponentEllipse].self, forKey: .ellipseArray
        )
        arcArray = try container.decode([HwpShapeComponentArc].self, forKey: .arcArray)
        polygonArray = try container.decode(
            [HwpShapeComponentPolygon].self, forKey: .polygonArray
        )
        curveArray = try container.decode([HwpShapeComponentCurve].self, forKey: .curveArray)
        oleArray = try container.decode([HwpShapeComponentOLE].self, forKey: .oleArray)
        oleRecords = try container.decode([HwpUnknownRecord].self, forKey: .oleRecords)
        containerArray = try container.decode(
            [HwpShapeComponentContainer].self, forKey: .containerArray
        )
        chartDataArray = try container.decode(
            [HwpShapeComponentChartData].self, forKey: .chartDataArray
        )
        textartArray = try container.decode(
            [HwpShapeComponentTextart].self, forKey: .textartArray
        )
        formObjectArray = try container.decode(
            [HwpShapeComponentFormObject].self, forKey: .formObjectArray
        )
        memoShapeArray = try container.decode(
            [HwpShapeComponentMemoShape].self, forKey: .memoShapeArray
        )
        memoListArray = try container.decode(
            [HwpShapeComponentMemoList].self, forKey: .memoListArray
        )
        videoDataArray = try container.decode(
            [HwpShapeComponentVideoData].self, forKey: .videoDataArray
        )
        shapeComponentUnknownArray = try container.decode(
            [HwpShapeComponentUnknown].self, forKey: .shapeComponentUnknownArray
        )
        ctrlDataRecords = try container.decode([HwpCtrlData].self, forKey: .ctrlDataRecords)
        // 글상자 리스트는 파스가 표 90을 무조건 파생한다 (nil ⟺ 파생도 nil) —
        // legacy 아카이브(textBoxInfo 키 부재)도 같은 파생으로 재수화하면 파스와
        // 멱등이다. 글상자 아닌 리스트(HwpListControl 소속 머리말/꼬리말)는 이
        // 경로를 타지 않아 nil 계약이 유지된다 (R64 #3).
        textBoxListArray = try container.decode(
            [HwpListControlList].self, forKey: .textBoxListArray
        ).map { list in
            guard list.textBoxInfo == nil else { return list }
            var rehydrated = list
            rehydrated.textBoxInfo = HwpTextBoxListInfo.decode(from: list.header.rawTrailing)
            return rehydrated
        }
        unknownChildren = try container.decode([HwpUnknownRecord].self, forKey: .unknownChildren)
    }
}

extension HwpShapeComponent: HwpTagValidatedRecord {
    static let expectedTag: HwpSectionTag = .shapeComponent

    // MARK: loader contract exemption - preserves common shape-component payload as raw data

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        // detail 접근자가 load 반환 후 rawPayload를 다시 읽으므로 분리 복사한다.
        rawPayload = reader.options.decoupledPayload(try reader.readToEnd())
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

            let header = try HwpListHeader.load(child.payload, options: child.options)
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
                headerRawPayload: child.options.decoupledPayload(child.payload),
                headerUnknownChildren: child.children.map(HwpUnknownRecord.init),
                paragraphArray: paragraphs,
                textBoxInfo: HwpTextBoxListInfo.decode(from: header.rawTrailing)
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

extension HwpShapeComponentRectangle: HwpTagValidatedRecord {
    static let expectedTag: HwpSectionTag = .shapeComponentRectangle

    // MARK: loader contract exemption - rectangle component payload is raw-backed

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        // rectangleDetail이 load 반환 후 rawPayload를 다시 읽으므로 분리 복사한다.
        rawPayload = reader.options.decoupledPayload(try reader.readToEnd())
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}

/** OLE 개체 요소 */
public struct HwpShapeComponentOLE {
    /** 원본 payload */
    public var rawPayload: Data
    /**
     BinData id (표 118). 없을 수 있다.

     실제 파일의 layout은 속성 UInt32 + extent INT32 × 2 뒤 offset 12의 UInt16이다
     (스펙 표 118의 속성 UInt16는 오기).
     */
    public var binaryDataId: UInt32?
    /** 속성 뒤의 아직 해석하지 않은 payload */
    public var rawTrailing: Data?
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]
}

extension HwpShapeComponentOLE: HwpTagValidatedRecord {
    static let expectedTag: HwpSectionTag = .shapeComponentOle

    /** BinData id의 payload 내 offset (속성 UInt32 + extent INT32 × 2 = 12) */
    private static let binaryDataIdOffset = 12

    // MARK: loader contract exemption - OLE component payload is best-effort raw-backed

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        // 세부 디코딩 접근자가 load 반환 후 rawPayload를 다시 읽으므로 분리 복사한다.
        rawPayload = reader.options.decoupledPayload(try reader.readToEnd())
        binaryDataId = Self.binaryDataId(from: rawPayload)
        rawTrailing = Self.rawTrailing(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }

    private static func binaryDataId(from payload: Data) -> UInt32? {
        guard payload.count >= binaryDataIdOffset + MemoryLayout<UInt16>.size else {
            return nil
        }
        do {
            return UInt32(try payload.readLittleEndianUInt16(at: binaryDataIdOffset))
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

extension HwpShapeComponentPicture: HwpTagValidatedRecord {
    static let expectedTag: HwpSectionTag = .shapeComponentPicture

    // MARK: loader contract exemption - picture component payload is best-effort raw-backed

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        // pictureProperty가 load 반환 후 rawPayload를 다시 읽으므로 분리 복사한다.
        rawPayload = reader.options.decoupledPayload(try reader.readToEnd())
        binaryDataId = Self.binaryDataId(from: rawPayload)
        rawTrailing = Self.rawTrailing(from: rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
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

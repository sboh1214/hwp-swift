import Foundation
import OLEKit

/// HWP 문서 파일을 읽기 전용으로 표현하는 최상위 모델입니다.
public struct HwpFile: HwpPrimitive {
    public let fileHeader: HwpFileHeader
    public let docInfo: HwpDocInfo
    public let sectionArray: [HwpSection]
    public let summary: HwpSummary
    public let previewText: HwpPreviewText
    public let previewImage: HwpPreviewImage
    public let binaryDataArray: [HwpBinaryData]

    /// 비어 있는 기본 HWP 문서 모델을 생성합니다.
    public init() {
        fileHeader = HwpFileHeader()
        docInfo = HwpDocInfo()
        sectionArray = [HwpSection()]
        summary = HwpSummary()
        previewText = HwpPreviewText()
        previewImage = HwpPreviewImage()
        binaryDataArray = []
    }

    /// 파일 경로의 HWP 문서를 읽습니다.
    public init(fromPath filePath: String, readLimits: HwpReadLimits = .default) throws {
        try readLimits.validate()

        let ole: OLEFile
        do {
            ole = try OLEFile(filePath)
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
        do {
            try self.init(fromOLE: ole, readLimits: readLimits)
        } catch let error as HwpError {
            throw error
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
    }

    /// 메모리의 HWP 문서 데이터를 읽습니다.
    public init(fromData data: Data, readLimits: HwpReadLimits = .default) throws {
        try readLimits.validate()

        let ole = try coreHwpOLEFile(fromData: data)
        do {
            try self.init(fromOLE: ole, readLimits: readLimits)
        } catch let error as HwpError {
            throw error
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
    }

    /// `FileWrapper`로 전달된 HWP 문서를 읽습니다.
    public init(
        fromWrapper fileWrapper: FileWrapper,
        readLimits: HwpReadLimits = .default
    ) throws {
        try readLimits.validate()

        let ole = try coreHwpOLEFile(fromWrapper: fileWrapper)
        do {
            try self.init(fromOLE: ole, readLimits: readLimits)
        } catch let error as HwpError {
            throw error
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
    }

    private init(fromOLE ole: OLEFile, readLimits: HwpReadLimits = .default) throws {
        try readLimits.validate()

        let streams = try StreamReader.rootStreams(from: ole.root.children)
        let reader = StreamReader(ole, streams, readLimits: readLimits)

        let fileHeader = try HwpFileHeader.load(reader.getDataFromStream(.fileHeader, false))
        if let unsupportedFeature = fileHeader.fileProperty.unsupportedFeature {
            throw HwpError.unsupportedFeature(unsupportedFeature)
        }
        let isCompressed = fileHeader.fileProperty.isCompressed

        let docInfoData = try reader.getDataFromStream(.docInfo, isCompressed)
        let docInfo = try HwpDocInfo.load(docInfoData, fileHeader.version)
        let sectionDataArray = try reader.getDataFromStorage(
            .bodyText,
            isCompressed,
            expectedCount: Int(docInfo.documentProperties.sectionSize)
        )
        let summaryData = try reader.getOptionalDataFromStream(.summary, false)
        let previewTextData = try reader.getOptionalDataFromStream(.previewText, false)
        let previewImageData = try reader.getOptionalDataFromStream(.previewImage, false)
        let binaryData = try reader.getOptionalNamedDataFromStorage(.binData, false)

        try self.init(
            fileHeader: fileHeader,
            docInfo: docInfo,
            sectionDataArray: sectionDataArray,
            summaryData: summaryData,
            previewTextData: previewTextData,
            previewImageData: previewImageData,
            binaryData: binaryData
        )
    }

    init(
        fileHeader: HwpFileHeader,
        docInfoData: Data,
        sectionDataArray: [Data],
        summaryData: Data? = nil,
        previewTextData: Data? = nil,
        previewImageData: Data? = nil,
        binaryData: [(name: String, data: Data)] = []
    ) throws {
        if let unsupportedFeature = fileHeader.fileProperty.unsupportedFeature {
            throw HwpError.unsupportedFeature(unsupportedFeature)
        }

        let docInfo = try HwpDocInfo.load(docInfoData, fileHeader.version)
        try self.init(
            fileHeader: fileHeader,
            docInfo: docInfo,
            sectionDataArray: sectionDataArray,
            summaryData: summaryData,
            previewTextData: previewTextData,
            previewImageData: previewImageData,
            binaryData: binaryData
        )
    }

    init(
        fileHeader: HwpFileHeader,
        docInfo: HwpDocInfo,
        sectionDataArray: [Data],
        summaryData: Data? = nil,
        previewTextData: Data? = nil,
        previewImageData: Data? = nil,
        binaryData: [(name: String, data: Data)] = []
    ) throws {
        self.fileHeader = fileHeader

        if let unsupportedFeature = fileHeader.fileProperty.unsupportedFeature {
            throw HwpError.unsupportedFeature(unsupportedFeature)
        }

        self.docInfo = docInfo

        let expectedSectionCount = Int(docInfo.documentProperties.sectionSize)
        guard expectedSectionCount > 0 else {
            throw HwpError.invalidRecordTree(
                reason: "BodyText sectionSize \(expectedSectionCount) is invalid"
            )
        }
        if sectionDataArray.count != expectedSectionCount {
            let reason = "BodyText section count \(sectionDataArray.count) " +
                "!= sectionSize \(expectedSectionCount)"
            throw HwpError.invalidRecordTree(
                reason: reason
            )
        }
        sectionArray = try sectionDataArray.map { try HwpSection.load($0, fileHeader.version) }

        if let summaryData {
            summary = try HwpSummary.load(summaryData)
        } else {
            summary = HwpSummary()
        }

        if let previewTextData {
            previewText = try HwpPreviewText.load(previewTextData)
        } else {
            previewText = HwpPreviewText()
        }

        if let previewImageData {
            previewImage = try HwpPreviewImage.load(previewImageData)
        } else {
            previewImage = HwpPreviewImage()
        }

        binaryDataArray = binaryData.map { HwpBinaryData(name: $0.name, data: $0.data) }
    }
}

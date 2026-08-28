import Foundation
import OLEKit

/// HWP 문서 파일을 읽기 전용으로 표현하는 최상위 모델입니다.
public struct HwpFile: HwpPrimitive {
    public let fileHeader: HwpFileHeader
    public let docInfo: HwpDocInfo
    public let sectionArray: [HwpSection]
    /// 표시용 본문 (`ViewText` 스토리지 — 변경 추적 저장본 등).
    /// 있으면 한글.app은 BodyText 대신 이걸 그린다. 없으면 빈 배열.
    public let viewSectionArray: [HwpSection]
    public let summary: HwpSummary
    public let previewText: HwpPreviewText
    public let previewImage: HwpPreviewImage
    public let binaryDataArray: [HwpBinaryData]

    /// 렌더 대상 본문: ViewText가 있으면 ViewText, 없으면 BodyText (한글.app 동작)
    public var displaySectionArray: [HwpSection] {
        // ViewText(표시본)는 전 구역을 빠짐없이 담을 때만 렌더 본문으로 채택한다.
        // 부분/불완전 ViewText는 BodyText 구역을 조용히 누락시키므로 무시한다.
        !viewSectionArray.isEmpty && viewSectionArray.count == sectionArray.count
            ? viewSectionArray : sectionArray
    }

    /// 비어 있는 기본 HWP 문서 모델을 생성합니다.
    public init() {
        fileHeader = HwpFileHeader()
        docInfo = HwpDocInfo()
        sectionArray = [HwpSection()]
        viewSectionArray = []
        summary = HwpSummary()
        previewText = HwpPreviewText()
        previewImage = HwpPreviewImage()
        binaryDataArray = []
    }

    /// 파일 경로의 HWP 문서를 읽습니다.
    public init(fromPath filePath: String, readLimits: HwpReadLimits = .default) throws {
        try self.init(fromPath: filePath, options: HwpLoadOptions(readLimits: readLimits))
    }

    /// 파일 경로의 HWP 문서를 로드 옵션과 함께 읽습니다.
    ///
    /// 선두 바이트로 컨테이너를 자동 감지합니다 — ZIP(`PK`)이면 HWPX(OWPML)
    /// 파이프라인으로, 그 외는 종전의 OLE(HWP 5.0 바이너리) 파이프라인으로
    /// 읽습니다. 어느 쪽도 아닌 입력의 오류 표면은 종전과 같습니다
    /// (`invalidOLEFile`).
    public init(fromPath filePath: String, options: HwpLoadOptions) throws {
        try options.readLimits.validate()

        if HwpxFormatDetection.sniffFile(atPath: filePath) == .zip {
            try self.init(
                hwpxData: HwpxFormatDetection.hwpxData(atPath: filePath),
                options: options
            )
            return
        }

        let ole: OLEFile
        do {
            ole = try OLEFile(filePath)
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
        do {
            try self.init(fromOLE: ole, options: options)
        } catch let error as HwpError {
            throw error
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
    }

    /// 메모리의 HWP 문서 데이터를 읽습니다.
    public init(fromData data: Data, readLimits: HwpReadLimits = .default) throws {
        try self.init(fromData: data, options: HwpLoadOptions(readLimits: readLimits))
    }

    /// 메모리의 HWP 문서 데이터를 로드 옵션과 함께 읽습니다.
    /// 선두 바이트로 HWP(OLE)/HWPX(ZIP)를 자동 감지합니다.
    public init(fromData data: Data, options: HwpLoadOptions) throws {
        try options.readLimits.validate()

        if HwpxFormatDetection.sniff(data.prefix(8)) == .zip {
            try self.init(hwpxData: data, options: options)
            return
        }

        let ole = try coreHwpOLEFile(fromData: data)
        do {
            try self.init(fromOLE: ole, options: options)
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
        try self.init(fromWrapper: fileWrapper, options: HwpLoadOptions(readLimits: readLimits))
    }

    /// `FileWrapper`로 전달된 HWP 문서를 로드 옵션과 함께 읽습니다.
    /// 선두 바이트로 HWP(OLE)/HWPX(ZIP)를 자동 감지합니다.
    public init(fromWrapper fileWrapper: FileWrapper, options: HwpLoadOptions) throws {
        try options.readLimits.validate()

        if let contents = fileWrapper.regularFileContents,
           HwpxFormatDetection.sniff(contents.prefix(8)) == .zip
        {
            try self.init(hwpxData: contents, options: options)
            return
        }

        let ole = try coreHwpOLEFile(fromWrapper: fileWrapper)
        do {
            try self.init(fromOLE: ole, options: options)
        } catch let error as HwpError {
            throw error
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
    }

    private init(fromOLE ole: OLEFile, options: HwpLoadOptions = .default) throws {
        try options.readLimits.validate()

        let streams = try StreamReader.rootStreams(from: ole.root.children)
        let reader = StreamReader(ole, streams, readLimits: options.readLimits)

        let fileHeader = try HwpFileHeader.load(reader.getDataFromStream(.fileHeader, false))
        if let unsupportedFeature = fileHeader.fileProperty.unsupportedFeature {
            throw HwpError.unsupportedFeature(unsupportedFeature)
        }
        let isCompressed = fileHeader.fileProperty.isCompressed

        let docInfoData = try reader.getDataFromStream(.docInfo, isCompressed)
        let docInfo = try HwpDocInfo.load(docInfoData, fileHeader.version, options: options)
        let sectionDataArray = try reader.getDataFromStorage(
            .bodyText,
            isCompressed,
            expectedCount: Int(docInfo.documentProperties.sectionSize)
        )
        let summaryData = try reader.getOptionalDataFromStream(.summary, false)
        let previewTextData = try reader.getOptionalDataFromStream(.previewText, false)
        let previewImageData = try reader.getOptionalDataFromStream(.previewImage, false)
        let binaryDataCompression = Self.binaryDataCompressionByStreamId(
            docInfo: docInfo,
            storageIsCompressed: isCompressed
        )
        let binaryData = try reader.getOptionalNamedDataFromStorage(.binData) { name in
            guard let streamId = HwpBinaryData.metadata(from: name).streamId else {
                return false
            }
            return binaryDataCompression[streamId] ?? false
        }
        // ViewText는 optional·표시 전용이다 — read/압축 해제가 실패해도 (BodyText가
        // 유효하면) 파일 전체를 못 열게 하지 않고 빈 ViewText로 폴백한다. ViewText
        // 지원 전엔 열리던 파일이므로 (#7). 파싱 실패 폴백은 init 안에 별도로 있다.
        let viewTextData: [(name: String, data: Data)]
        do {
            viewTextData = try reader.getOptionalNamedDataFromStorage(
                .viewText, isCompressed, expectedChildCount: sectionDataArray.count
            )
        } catch let HwpError.streamSizeLimitExceeded(name, limit, actual) {
            // 자원 한계는 설정된 하드 한계이므로 optional ViewText라도 폴백하지
            // 않고 전파한다 — corrupt/unsupported ViewText만 아래 빈 폴백 (P1).
            throw HwpError.streamSizeLimitExceeded(name: name, limit: limit, actual: actual)
        } catch let HwpError.aggregateStreamSizeLimitExceeded(name, limit, actual) {
            throw HwpError.aggregateStreamSizeLimitExceeded(name: name, limit: limit, actual: actual)
        } catch {
            viewTextData = []
        }

        try self.init(
            fileHeader: fileHeader,
            docInfo: docInfo,
            sectionDataArray: sectionDataArray,
            summaryData: summaryData,
            previewTextData: previewTextData,
            previewImageData: previewImageData,
            binaryData: binaryData,
            viewTextData: viewTextData,
            options: options
        )
    }

    init(
        fileHeader: HwpFileHeader,
        docInfoData: Data,
        sectionDataArray: [Data],
        summaryData: Data? = nil,
        previewTextData: Data? = nil,
        previewImageData: Data? = nil,
        binaryData: [(name: String, data: Data)] = [],
        viewTextData: [(name: String, data: Data)] = [],
        options: HwpLoadOptions = .default
    ) throws {
        if let unsupportedFeature = fileHeader.fileProperty.unsupportedFeature {
            throw HwpError.unsupportedFeature(unsupportedFeature)
        }

        let docInfo = try HwpDocInfo.load(docInfoData, fileHeader.version, options: options)
        try self.init(
            fileHeader: fileHeader,
            docInfo: docInfo,
            sectionDataArray: sectionDataArray,
            summaryData: summaryData,
            previewTextData: previewTextData,
            previewImageData: previewImageData,
            binaryData: binaryData,
            viewTextData: viewTextData,
            options: options
        )
    }

    init(
        fileHeader: HwpFileHeader,
        docInfo: HwpDocInfo,
        sectionDataArray: [Data],
        summaryData: Data? = nil,
        previewTextData: Data? = nil,
        previewImageData: Data? = nil,
        binaryData: [(name: String, data: Data)] = [],
        viewTextData: [(name: String, data: Data)] = [],
        options: HwpLoadOptions = .default
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
        sectionArray = try sectionDataArray.map {
            // 복구 모드에서는 구역 하나의 파싱 실패가 문서 전체를 실패시키지
            // 않도록 placeholder 구역으로 대체한다. 자원 한도 등
            // recovery-exempt 오류는 계속 전파한다 (#65).
            do {
                return try HwpSection.load($0, fileHeader.version, options: options)
            } catch let error as HwpError
                where options.recoverPartialContent && !error.isRecoveryExempt
            {
                return HwpSection.parseFailurePlaceholder(
                    error: error,
                    rawPayload: options.preservedPayload($0)
                )
            }
        }
        viewSectionArray = Self.parseViewSections(
            viewTextData,
            expectedSectionCount: expectedSectionCount,
            version: fileHeader.version,
            options: options
        )

        if let summaryData {
            summary = try HwpSummary.load(summaryData, options: options)
        } else {
            summary = HwpSummary()
        }

        if let previewTextData {
            previewText = try HwpPreviewText.load(previewTextData, options: options)
        } else {
            previewText = HwpPreviewText()
        }

        if let previewImageData {
            previewImage = try HwpPreviewImage.load(previewImageData, options: options)
        } else {
            previewImage = HwpPreviewImage()
        }

        binaryDataArray = binaryData.map { HwpBinaryData(name: $0.name, data: $0.data) }
    }

    /// 표시용 본문 (ViewText): 이름이 Section0…Section{N-1}과 정확히
    /// (개수·연속·중복 없이) 일치할 때만 best-effort 파싱한다. 개수만 같고
    /// 이름이 누락/중복/비-section이면 BodyText 구역을 조용히 잘못 대체하므로
    /// 무시한다 (#17). 파싱 실패 시에도 BodyText 렌더로 폴백한다.
    ///
    /// ViewText에는 복구를 켜지 않는다 — 실패 구역·문단을 placeholder로
    /// 채우면 개수 보존 탓에 채택 규칙(`displaySectionArray`)을 통과한
    /// 불완전 표시본이 그 구역을 백지로 만든다. BodyText 복구본으로
    /// 강등하는 기존 전량 폐기가 안전하다 (#65).
    private static func parseViewSections(
        _ viewTextData: [(name: String, data: Data)],
        expectedSectionCount: Int,
        version: HwpVersion,
        options: HwpLoadOptions
    ) -> [HwpSection] {
        var viewTextOptions = options
        viewTextOptions.recoverPartialContent = false
        let sortedViewText = viewTextData.sorted { lhs, rhs in
            sectionIndex(from: lhs.name) < sectionIndex(from: rhs.name)
        }
        guard sortedViewText.map(\.name)
            == (0 ..< expectedSectionCount).map({ "Section\($0)" })
        else {
            return []
        }
        do {
            return try sortedViewText.map {
                try HwpSection.load($0.data, version, options: viewTextOptions)
            }
        } catch {
            return []
        }
    }

    /// "Section12" → 12 (숫자 없으면 Int.max — 뒤로 보냄)
    private static func sectionIndex(from name: String) -> Int {
        guard name.hasPrefix("Section"), let index = Int(name.dropFirst("Section".count))
        else { return Int.max }
        return index
    }

    static func binaryDataCompressionByStreamId(
        docInfo: HwpDocInfo,
        storageIsCompressed: Bool
    ) -> [UInt16: Bool] {
        var compressionByStreamId = [UInt16: Bool]()
        for binData in docInfo.idMappings.binDataArray {
            guard let streamId = binData.streamId else {
                continue
            }
            switch binData.property.compressType {
            case .always:
                compressionByStreamId[streamId] = true
            case .followStorage:
                compressionByStreamId[streamId] = storageIsCompressed
            case .never:
                compressionByStreamId[streamId] = false
            }
        }
        return compressionByStreamId
    }
}

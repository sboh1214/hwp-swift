import Foundation
import OLEKit

/**
 3.2.1. 파일 인식 정보

 한글의 문서 파일이라는 것을 나타내기 위해 ‘파일 인식 정보’가 저장된다.
 */
public struct HwpFileHeader: HwpFromData {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /**
     signature

     문서 파일은 "HWP Document File"
     */
    public var signature: String
    public var version: HwpVersion

    public var fileProperty: HwpFileProperty

    public var fileLicense: HwpFileLicense

    /**
     EncryptVersion
     - 0 : None
     - 1 : (한글 2.5 버전 이하)
     - 2 : (한글 3.0 버전 Enhanced)
     - 3 : (한글 3.0 버전 Old)
     - 4 : (한글 7.0 버전 이후)
     */
    public var encryptVersion: UInt32
    /** 공공누리 Korea Open Government License */
    public var koreaOpenLicense: UInt8

    /** 아직 해석하지 않은 예약 영역 */
    @ExcludeEquatable
    public var reserved: Data

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        let signatureData = try reader.readBytes(32)
        guard let signature = signatureData.stringASCII else {
            throw HwpError.invalidDataForString(data: signatureData, name: "signature")
        }
        self.signature = signature
        if signature != "HWP Document File\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" {
            throw HwpError.invalidFileHeaderSignature(signature: signature)
        }

        version = try HwpVersion.load(try reader.readBytes(4))

        fileProperty = try HwpFileProperty.load(try reader.read(DWORD.self))
        fileLicense = try HwpFileLicense.load(try reader.read(DWORD.self))

        encryptVersion = try reader.read(UInt32.self)
        koreaOpenLicense = try reader.read(UInt8.self)

        reserved = try reader.readBytes(207)
        rawPayload = try reader.consumedData(from: startOffset)
    }
}

extension HwpFileHeader {
    init() {
        rawPayload = Data()
        signature = "HWP Document File\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
        version = HwpVersion()

        fileProperty = HwpFileProperty()
        fileLicense = HwpFileLicense()

        encryptVersion = 4
        koreaOpenLicense = 0
        reserved = Data(repeating: 0, count: 207)
    }

    static func load(fromPath filePath: String) throws -> Self {
        let ole: OLEFile
        do {
            ole = try OLEFile(filePath)
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
        return try load(fromOLE: ole)
    }

    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        static func load(fromData data: Data) throws -> Self {
            let fileWrapper = FileWrapper(regularFileWithContents: data)
            fileWrapper.preferredFilename = "document.hwp"
            return try load(fromWrapper: fileWrapper)
        }

        static func load(fromWrapper fileWrapper: FileWrapper) throws -> Self {
            let ole: OLEFile
            do {
                ole = try OLEFile(fileWrapper)
            } catch {
                throw HwpError.invalidOLEFile(reason: String(describing: error))
            }
            return try load(fromOLE: ole)
        }
    #endif

    private static func load(fromOLE ole: OLEFile) throws -> Self {
        let streams = try StreamReader.rootStreams(from: ole.root.children)
        let reader = StreamReader(ole, streams)
        return try load(reader.getDataFromStream(.fileHeader, false))
    }
}

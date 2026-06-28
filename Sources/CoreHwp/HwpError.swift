import Foundation

/// 읽기 전용 reader가 지원하지 않는 HWP 보안/배포 기능입니다.
public enum HwpUnsupportedFeature: String, HwpPrimitive {
    /// 암호로 보호된 문서입니다.
    case encryptedDocument
    /// 배포용 문서입니다.
    case deploymentDocument
    /// DRM 또는 공인 인증서 DRM이 적용된 문서입니다.
    case drmDocument
}

/// HWP 파일을 읽는 동안 발생할 수 있는 typed error입니다.
public enum HwpError: Error {
    case streamDoesNotExist(name: HwpStreamName)
    case streamDecompressFailed(name: HwpStreamName)
    case streamSizeLimitExceeded(name: HwpStreamName, limit: Int, actual: Int)
    case invalidOLEFile(reason: String)
    case invalidDataForString(data: Data, name: String)
    case recordDoesNotExist(tag: UInt32)
    case invalidRecordTree(reason: String)
    case invalidFileHeaderSignature(signature: String)
    case invalidUnicodeScalar(value: UInt16)
    case unidentifiedTag(tagId: UInt32)
    case invalidCtrlId(ctrlId: UInt32)
    case truncatedData(expected: Int, actual: Int)
    case truncatedBits(expected: Int, actual: Int)
    case invalidDataLength(length: String)
    case unsupportedDataReadType(type: String)
    case unsupportedFeature(HwpUnsupportedFeature)
    case bytesAreNotEOF(modelName: String, remain: Int)
    case bitsAreNotEOF(modelName: String, remain: Int)
    case invalidRawValueForEnum(modelName: String, rawValue: Int)
}

extension HwpError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .streamDoesNotExist(name):
            "Stream '\(name)' does not exist"
        case let .streamDecompressFailed(name):
            "Stream '\(name)' failed to decompress"
        case let .streamSizeLimitExceeded(name, limit, actual):
            "Stream '\(name)' exceeded size limit: \(actual) bytes > \(limit) bytes"
        case let .invalidOLEFile(reason):
            "Invalid OLE file: \(reason)"
        case let .invalidDataForString(data, name):
            """
            Cannot convert data to utf16le string
            data: '\(data)'
            name: '\(name)'
            """
        case let .recordDoesNotExist(tag):
            "Record '\(tag)' does not exist."
        case let .invalidRecordTree(reason):
            "Invalid record tree: \(reason)"
        case let .invalidFileHeaderSignature(signature):
            "Invalid signature in FileHeader stream : get'\(signature)'"
        case let .invalidUnicodeScalar(value):
            "Invalid Unicode scalar value for WCHAR: \(value)"
        case let .unidentifiedTag(tagId):
            "Cannot Read HwpRecord Tag : '\(tagId)'"
        case let .invalidCtrlId(ctrlId):
            "Invalid Ctrl Id in HwpParagraph : '\(ctrlId)'"
        case let .truncatedData(expected, actual):
            "Truncated data: expected \(expected) bytes, got \(actual) bytes"
        case let .truncatedBits(expected, actual):
            "Truncated bits: expected \(expected) bits, got \(actual) bits"
        case let .invalidDataLength(length):
            "Invalid data length: \(length)"
        case let .unsupportedDataReadType(type):
            "Unsupported data read type: \(type)"
        case let .unsupportedFeature(feature):
            "Unsupported HWP feature: \(feature.rawValue)"
        case let .bytesAreNotEOF(modelName, remain):
            "Bytes are not EOF : \(remain) bytes remain in \(modelName)"
        case let .bitsAreNotEOF(modelName, remain):
            "Bits are not EOF : \(remain) bits remain in \(modelName)"
        case let .invalidRawValueForEnum(modelName, rawValue):
            "Invalid rawValue : \(rawValue) for initiating enum : \(modelName)"
        }
    }
}

extension HwpError {
    static func bytesAreNotEOF(model: Any, remain: Int) -> HwpError {
        .bytesAreNotEOF(modelName: hwpErrorModelName(model), remain: remain)
    }

    static func bitsAreNotEOF(model: Any, remain: Int) -> HwpError {
        .bitsAreNotEOF(modelName: hwpErrorModelName(model), remain: remain)
    }

    static func invalidRawValueForEnum(model: Any, rawValue: Int) -> HwpError {
        .invalidRawValueForEnum(modelName: hwpErrorModelName(model), rawValue: rawValue)
    }
}

extension HwpError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

private func hwpErrorModelName(_ model: Any) -> String {
    if let modelType = model as? Any.Type {
        return String(describing: modelType)
    }
    return String(describing: type(of: model))
}

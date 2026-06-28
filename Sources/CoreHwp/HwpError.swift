import Foundation

public enum HwpUnsupportedFeature: String, HwpPrimitive {
    case encryptedDocument
    case deploymentDocument
    case drmDocument
}

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
    case bytesAreNotEOF(model: Any, remain: Int)
    case bitsAreNotEOF(model: Any, remain: Int)
    case invalidRawValueForEnum(model: Any, rawValue: Int)
}

extension HwpError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .streamDoesNotExist(name):
            return "Stream '\(name)' does not exist"
        case let .streamDecompressFailed(name):
            return "Stream '\(name)' failed to decompress"
        case let .streamSizeLimitExceeded(name, limit, actual):
            return "Stream '\(name)' exceeded size limit: \(actual) bytes > \(limit) bytes"
        case let .invalidOLEFile(reason):
            return "Invalid OLE file: \(reason)"
        case let .invalidDataForString(data, name):
            return
                """
                Cannot convert data to utf16le string
                data: '\(data)'
                name: '\(name)'
                """
        case let .recordDoesNotExist(tag):
            return "Record '\(tag)' does not exist."
        case let .invalidRecordTree(reason):
            return "Invalid record tree: \(reason)"
        case let .invalidFileHeaderSignature(signature):
            return "Invalid signature in FileHeader stream : get'\(signature)'"
        case let .invalidUnicodeScalar(value):
            return "Invalid Unicode scalar value for WCHAR: \(value)"
        case let .unidentifiedTag(tagId):
            return "Cannot Read HwpRecord Tag : '\(tagId)'"
        case let .invalidCtrlId(ctrlId):
            return "Invalid Ctrl Id in HwpParagraph : '\(ctrlId)'"
        case let .truncatedData(expected, actual):
            return "Truncated data: expected \(expected) bytes, got \(actual) bytes"
        case let .truncatedBits(expected, actual):
            return "Truncated bits: expected \(expected) bits, got \(actual) bits"
        case let .invalidDataLength(length):
            return "Invalid data length: \(length)"
        case let .unsupportedDataReadType(type):
            return "Unsupported data read type: \(type)"
        case let .unsupportedFeature(feature):
            return "Unsupported HWP feature: \(feature.rawValue)"
        case let .bytesAreNotEOF(model, remain):
            let typeOfModel = hwpErrorModelName(model)
            return "Bytes are not EOF : \(remain) bytes remain in \(typeOfModel)"
        case let .bitsAreNotEOF(model, remain):
            let typeOfModel = hwpErrorModelName(model)
            return "Bits are not EOF : \(remain) bits remain in \(typeOfModel)"
        case let .invalidRawValueForEnum(model, rawValue):
            let typeOfModel = hwpErrorModelName(model)
            return "Invalid rawValue : \(rawValue) for initiating enum : \(typeOfModel)"
        }
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

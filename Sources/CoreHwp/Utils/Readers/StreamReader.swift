import Foundation
import OLEKit
import SWCompression

struct StreamReader {
    private let ole: OLEFile
    private let streams: [String: DirectoryEntry]

    init(_ ole: OLEFile, _ streams: [String: DirectoryEntry]) {
        self.ole = ole
        self.streams = streams
    }

    func getDataFromStream(_ streamName: HwpStreamName, _ isCompressed: Bool) throws -> Data {
        guard let stream = streams[streamName.rawValue] else {
            throw HwpError.streamDoesNotExist(name: streamName)
        }
        return try readData(stream, isCompressed)
    }

    func getDataFromStorage(_ streamName: HwpStreamName, _ isCompressed: Bool) throws -> [Data] {
        guard let storage = streams[streamName.rawValue] else {
            throw HwpError.streamDoesNotExist(name: streamName)
        }
        return try storage.children.map { try readData($0, isCompressed) }
    }

    private func readData(_ stream: DirectoryEntry, _ isCompressed: Bool) throws -> Data {
        let reader = try ole.stream(stream)
        let data = reader.readDataToEnd()
        if isCompressed {
            return try Deflate.decompress(data: data)
        } else {
            return data
        }
    }
}

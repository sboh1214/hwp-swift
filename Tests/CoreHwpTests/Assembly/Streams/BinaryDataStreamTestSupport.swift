@testable import CoreHwp
import Foundation

func readBinaryDataStreams(
    _ reader: StreamReader,
    docInfo: HwpDocInfo,
    storageIsCompressed: Bool
) throws -> [(name: String, data: Data)] {
    let compressionByStreamId = HwpFile.binaryDataCompressionByStreamId(
        docInfo: docInfo,
        storageIsCompressed: storageIsCompressed
    )
    return try reader.getOptionalNamedDataFromStorage(.binData) { name in
        guard let streamId = HwpBinaryData.metadata(from: name).streamId else {
            return false
        }
        return compressionByStreamId[streamId] ?? false
    }
}

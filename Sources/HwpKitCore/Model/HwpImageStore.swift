@preconcurrency import CoreHwp
import Foundation

/// BinItem id (DocInfo HWPTAG_BIN_DATA 참조값, 1-based) → 이미지 바이트 매핑.
///
/// 그림 컨트롤의 `binItemId` → DocInfo binData 항목의 `streamId` →
/// BinData 스토리지 스트림 순으로 조인한 결과를 보관한다.
/// LINK 타입(외부 파일)이나 스트림이 없는 항목은 포함되지 않는다.
public struct HwpImageStore: Sendable {
    /// binItemId(1-based) → 압축 해제된 이미지 payload
    public let dataByBinItemId: [UInt32: Data]
    /// binItemId(1-based) → 확장자 (jpg/png/bmp/gif 등, 소문자 아님 그대로)
    public let extensionByBinItemId: [UInt32: String]

    public init(
        dataByBinItemId: [UInt32: Data] = [:],
        extensionByBinItemId: [UInt32: String] = [:]
    ) {
        self.dataByBinItemId = dataByBinItemId
        self.extensionByBinItemId = extensionByBinItemId
    }

    public init(from file: CoreHwp.HwpFile) {
        var dataById: [UInt32: Data] = [:]
        var extensionById: [UInt32: String] = [:]
        let streams = Dictionary(
            file.binaryDataArray.compactMap { stream -> (UInt16, Data)? in
                guard let streamId = stream.streamId else { return nil }
                return (streamId, stream.data)
            },
            uniquingKeysWith: { first, _ in first }
        )
        for (index, entry) in file.docInfo.idMappings.binDataArray.enumerated() {
            let binItemId = UInt32(index + 1)
            if let extensionName = entry.extensionName {
                extensionById[binItemId] = extensionName
            }
            guard let streamId = entry.streamId, let data = streams[streamId] else { continue }
            dataById[binItemId] = data
        }
        dataByBinItemId = dataById
        extensionByBinItemId = extensionById
    }

    public var isEmpty: Bool {
        dataByBinItemId.isEmpty
    }

    public func data(forBinItemId id: UInt32) -> Data? {
        dataByBinItemId[id]
    }

    public func extensionName(forBinItemId id: UInt32) -> String? {
        extensionByBinItemId[id]
    }
}

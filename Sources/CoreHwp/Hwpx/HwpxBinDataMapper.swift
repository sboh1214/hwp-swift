import Foundation

/// manifest의 `BinData/*` 항목을 HWP5식 BinItem id 공간으로 옮긴 결과.
///
/// 렌더 스택의 그림 경로는 `binItemId = idMappings.binDataArray의 offset+1`
/// → 그 항목의 `streamId` → `HwpBinaryData.streamId`(이름 `BIN%04X.ext`에서
/// 파생) 조인으로 닫힌다 (`HwpImageStore`). 그래서 manifest 등재 순서 k의
/// 항목에 `streamId = k+1`을 부여하고 같은 이름 규칙으로 스트림을 만들면
/// HWP5 경로가 무변경으로 성립한다.
struct HwpxBinDataCatalog {
    /// `idMappings.binDataArray`에 들어갈 항목 — manifest 순서.
    var binDataArray: [HwpBinData] = []
    /// `HwpFile.binaryDataArray`에 들어갈 스트림 — 엔트리가 실재하는 것만.
    var binaryDataArray: [HwpBinaryData] = []
    /// manifest item id → BinItem id (1-based). `hp:pic`의
    /// `binaryItemIDRef`를 표 107 payload의 binItemId로 바꿀 때 쓴다.
    var binItemIdByManifestId: [String: UInt16] = [:]
}

enum HwpxBinDataMapper {
    static func map(
        manifest: HwpxManifest,
        container: inout HwpxContainer
    ) throws -> HwpxBinDataCatalog {
        var catalog = HwpxBinDataCatalog()
        for (index, item) in manifest.binDataItems.enumerated() {
            // BinItem id는 16비트다 — 65,535개를 넘는 첨부는 id 공간 자체가
            // 없으므로 이후 항목은 싣지 않는다 (실문서에서는 도달 불능).
            guard let binItemId = UInt16(exactly: index + 1) else {
                break
            }

            var meta = HwpBinData()
            var property = HwpBinDataProperty()
            property.type = .embedding
            property.compressType = .followStorage
            property.state = .never
            meta.property = property
            meta.streamId = binItemId
            let extensionName = Self.extensionName(of: item.href)
            meta.extensionName = extensionName
            catalog.binDataArray.append(meta)
            if !item.id.isEmpty, catalog.binItemIdByManifestId[item.id] == nil {
                catalog.binItemIdByManifestId[item.id] = binItemId
            }

            // 엔트리가 없는 항목은 메타만 남긴다 — id 공간(offset+1)이
            // 밀리면 뒤 그림 전부가 엉뚱한 스트림에 조인되므로 배열에서
            // 빼는 대신 스트림 쪽을 비워 placeholder로 강등시킨다.
            guard let payload = try container.optionalEntry(item.href) else {
                continue
            }
            catalog.binaryDataArray.append(HwpBinaryData(
                name: String(format: "BIN%04X.%@", binItemId, extensionName),
                data: payload
            ))
        }
        return catalog
    }

    /// href의 확장자 — `HwpBinaryData.metadata(from:)`가 요구하는 비어 있지
    /// 않은 한 조각이어야 하므로 없거나 비면 `bin`으로 대체한다.
    static func extensionName(of href: String) -> String {
        let lastComponent = href.split(separator: "/").last ?? ""
        let parts = lastComponent.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let ext = parts.last, !ext.isEmpty else {
            return "bin"
        }
        return String(ext)
    }
}

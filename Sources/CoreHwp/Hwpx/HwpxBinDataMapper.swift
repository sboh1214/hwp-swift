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
        let binDataItems = manifest.binDataItems
        // BinItem id는 1-based 16비트라 65,536번째부터는 id 공간이 없다.
        // 조용히 자르면 그 항목을 참조하는 그림이 id 0으로 떨어져 사라지는데
        // 문서는 성공한 파스로 보고된다 — 다른 가족 가드처럼 거부한다.
        guard binDataItems.count <= Int(UInt16.max) else {
            throw HwpError.invalidXML(
                entry: manifest.entry,
                reason: "BinData items exceed the 65,535-entry ID space"
            )
        }
        for (index, item) in binDataItems.enumerated() {
            // 위 가드가 index + 1 <= 65,535를 보장한다.
            let binItemId = UInt16(index + 1)

            var meta = HwpBinData()
            var property = HwpBinDataProperty()
            property.type = .embedding
            // 실물 한/글 저장본이 임베드 그림에 쓰는 값이다 (BinData 픽스처의
            // HWP5 원본 3항목 전부 property raw 33 = embedding·never·never).
            // 의미로도 맞다 — HWPX는 zip이 이미 푼 바이트를 그대로 싣는데
            // `.followStorage`는 스토리지 기본값이 압축이면 그 바이트를 또
            // 풀라는 표시가 된다 (`binaryDataCompressionByStreamId`).
            property.compressType = .never
            property.state = .never
            // typed가 확정된 뒤 raw를 합성한다 — 안 하면 raw 0이 `.link`로
            // 디코드돼, 링크가 가질 수 없는 streamId·extensionName을 단
            // 자기모순 상태가 공개 API로 나간다 (바이너리는 `load(_:)`가
            // 채운다). raw/typed를 함께 세우는 다른 매퍼 넷과 같은 계열이다.
            property.rawValue = property.synthesizedRawValue
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
            //
            // href는 URI가 아니라 **엔트리 이름 그대로** 대조한다. 한글.app
            // 12.30 실측(BinData 픽스처 A/B 사본): 엔트리가
            // `BinData/my image1.png`일 때 href를 `my%20image1.png`로 적은
            // 사본은 그림이 빈 프레임이 되고, 공백 그대로 적은 사본만 그려졌다
            // — 정본 렌더러도 문자 그대로 대조한다. percent-decode를 넣으면
            // 한글이 못 그리는 그림을 우리만 그리고(역방향 divergence), 이름에
            // `%`가 든 실재 엔트리는 반대로 못 찾으며, `%2F`는 `BinData/`
            // 분류까지 흔든다. 실물 픽스처 10종의 href도 전수 리터럴 일치다.
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

import Foundation

/// HWPX(OCF+OWPML) 바이트에서 `HwpFile`을 조립한다 — HWPX 파이프라인의
/// 진입점이다. 컨테이너 게이트 → version/manifest/BinData → header →
/// 구역 순서로, 바이너리 `init(fromOLE:)`가 stream을 잇는 순서와 대응한다.
extension HwpFile {
    init(hwpxData data: Data, options: HwpLoadOptions) throws {
        try options.readLimits.validate()
        var container = try HwpxContainer(data: data, limits: options.readLimits)

        let version = try HwpxVersionMapper.version(
            fromVersionXML: container.optionalEntry(HwpxContainer.EntryName.version)
        )
        let fileHeader = HwpxVersionMapper.fileHeader(version: version)

        let manifest = try HwpxManifest.parse(
            container.requiredEntry(HwpxContainer.EntryName.manifest)
        )
        let catalog = try HwpxBinDataMapper.map(manifest: manifest, container: &container)

        // 구역 순서의 정본은 spine이지만, spine이 아카이브 실재 구역을
        // 빠뜨리면 그 구역이 조용히 사라진다 — spine 순서를 그대로 두고
        // 누락분만 숫자 순으로 뒤에 병합한다 (`sectionEntryNames` 계약).
        var sectionNames = manifest.sectionHrefs
        let listed = Set(sectionNames)
        sectionNames += container.sectionEntryNames.filter { !listed.contains($0) }
        guard !sectionNames.isEmpty else {
            throw HwpError.archiveEntryDoesNotExist(name: "Contents/section0.xml")
        }

        let (docInfo, idTables) = try HwpxHeaderMapper.map(
            container.requiredEntry(HwpxContainer.EntryName.header),
            binDataCatalog: catalog,
            options: options,
            sectionCount: sectionNames.count
        )

        var sections: [HwpSection] = []
        for name in sectionNames {
            // entry 읽기도 복구 경계 안이다 — spine이 가리키는 구역이
            // 아카이브에 없거나 deflate가 손상되면 매핑에 닿기 전에 던져져,
            // 매핑만 감쌌을 때는 복구가 통째로 우회된다. 자원 한도·미지원
            // (isRecoveryExempt)은 여기서도 그대로 전파된다.
            let sectionData: Data
            do {
                sectionData = try container.requiredEntry(name)
            } catch let error as HwpError
                where options.recoverPartialContent && !error.isRecoveryExempt
            {
                // entry 자체를 읽지 못했으므로 rawPayload에 남길 원본이 없다.
                sections.append(HwpSection.parseFailurePlaceholder(error: error))
                continue
            }
            let context = HwpxMappingContext(
                idTables: idTables,
                binItemIdByManifestId: catalog.binItemIdByManifestId,
                options: options,
                entry: name
            )
            // 복구 모드에서 구역 하나의 실패가 문서 전체를 실패시키지 않도록
            // placeholder 구역으로 대체한다 — 바이너리 경로와 같은 규약 (#65).
            do {
                sections.append(try HwpxSectionMapper.map(sectionData, context: context))
            } catch let error as HwpError
                where options.recoverPartialContent && !error.isRecoveryExempt
            {
                sections.append(HwpSection.parseFailurePlaceholder(
                    error: error,
                    rawPayload: options.preservedPayload(sectionData)
                ))
            }
        }

        let previewText = HwpxPreviewMapper.previewText(
            from: try container.optionalEntry(HwpxContainer.EntryName.previewText)
        )
        let previewImage = HwpxPreviewMapper.previewImage(
            from: try container.optionalEntry(HwpxContainer.EntryName.previewImage)
        )

        self.init(
            hwpxFileHeader: fileHeader,
            docInfo: docInfo,
            sectionArray: sections,
            previewText: previewText,
            previewImage: previewImage,
            binaryDataArray: catalog.binaryDataArray
        )
    }

    /// HWPX 조립 전용 — HWPX에는 ViewText·요약 stream이 없다.
    init(
        hwpxFileHeader fileHeader: HwpFileHeader,
        docInfo: HwpDocInfo,
        sectionArray: [HwpSection],
        previewText: HwpPreviewText,
        previewImage: HwpPreviewImage,
        binaryDataArray: [HwpBinaryData]
    ) {
        self.fileHeader = fileHeader
        self.docInfo = docInfo
        self.sectionArray = sectionArray
        viewSectionArray = []
        summary = HwpSummary()
        self.previewText = previewText
        self.previewImage = previewImage
        self.binaryDataArray = binaryDataArray
    }
}

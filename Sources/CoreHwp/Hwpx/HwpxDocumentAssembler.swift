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

        // 구역 순서의 정본은 spine이고, spine이 비면 아카이브의
        // section{N}.xml 숫자 정렬로 폴백한다.
        var sectionNames = manifest.sectionHrefs
        if sectionNames.isEmpty {
            sectionNames = container.sectionEntryNames
        }
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
            let sectionData = try container.requiredEntry(name)
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

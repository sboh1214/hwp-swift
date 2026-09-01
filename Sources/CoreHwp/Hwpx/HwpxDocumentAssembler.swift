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

        let packageName = try container.packageEntryName()
        let manifest = try HwpxManifest.parse(
            container.requiredEntry(packageName), entry: packageName
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

        // 헤더도 선언이 정본이다 — 관례 경로만 보면 재포장 컨테이너에서
        // 낡은 Contents/header.xml의 스타일·id 테이블을 조용히 쓰고, 선언
        // href가 관례가 아니면 있는 헤더를 못 찾는다 (낡은 패키지 문서와
        // 같은 계열). 선언이 없으면 관례로 폴백한다 — spine 제외와 같은 값.
        let headerName = manifest.resolvedHeaderHref
        let (docInfo, idTables) = try HwpxHeaderMapper.map(
            container.requiredEntry(headerName),
            binDataCatalog: catalog,
            options: options,
            sectionCount: sectionNames.count,
            entry: headerName
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

        // options를 넘겨야 `.viewer`의 payload 게이트가 미리보기에도 걸린다 —
        // 빠뜨리면 바이너리 경로와 달리 미리보기 payload가 통째로 상주한다.
        let previewText = HwpxPreviewMapper.previewText(
            from: try container.optionalEntry(HwpxContainer.EntryName.previewText),
            options: options
        )
        let previewImage = HwpxPreviewMapper.previewImage(
            from: try container.optionalEntry(HwpxContainer.EntryName.previewImage),
            options: options
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

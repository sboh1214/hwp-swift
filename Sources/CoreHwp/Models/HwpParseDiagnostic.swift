import Foundation

/// 파서가 해석하지 못한 요소 하나에 대한 진단.
///
/// `HwpFile.parseDiagnostics()`가 문서 전체를 순회해 만든다. 렌더 스택의
/// `HwpUnsupportedDetector` 계열이 "미지원 요소가 화면에서 placeholder로
/// 보이는가"(뷰어 UI)를 다루는 것과 달리, 이 타입은 조판과 무관하게 "파서가
/// 무엇을 해석하지 못했는가"(QA·텔레메트리·버그 리포트·픽스처 회귀 신호)를
/// 다룬다 (#66).
public struct HwpParseDiagnostic: HwpPrimitive {
    /// 진단 종류.
    public enum Kind: String, HwpPrimitive {
        /// 해석하지 못하고 raw payload로 보존한 record
        /// (`unknownRecords`·`unknownChildren`와 그 하위 record)
        case unknownRecord
        /// ctrl id 자체를 알지 못하는 컨트롤 (`HwpCtrlId.unknown`)
        case unknownControl
        /// ctrl id는 알지만 typed 파싱이 없거나 raw 폴백으로 보존한 컨트롤
        /// (`HwpCtrlId.notImplemented`)
        case notImplementedControl
        /// 복구 모드(#65)에서 구역 전체가 placeholder로 대체됨
        case recoveredSection
        /// 복구 모드에서 문단이 placeholder로 대체됨
        case recoveredParagraph
        /// 복구 모드에서 메모 본문 문단이 placeholder로 대체됨
        case recoveredMemoParagraph
    }

    public let kind: Kind
    /// unknown record의 tag ID. record 진단이 아니면 nil.
    public let tagId: UInt32?
    /// 컨트롤 진단의 4-byte ctrl ID. 컨트롤 진단이 아니면 nil.
    public let ctrlId: UInt32?
    /// 요소 위치. 예: `"section[0].paragraph[12].ctrl[1].cell[0].paragraph[0]"`.
    /// BodyText는 `section[i]`, ViewText 표시본은 `viewSection[i]`,
    /// DocInfo는 `docInfo`로 시작한다.
    public let path: String
    /// 부가 정보 (placeholder의 `parseFailure` 사유 등). 없으면 nil.
    public let detail: String?

    public init(
        kind: Kind,
        tagId: UInt32? = nil,
        ctrlId: UInt32? = nil,
        path: String,
        detail: String? = nil
    ) {
        self.kind = kind
        self.tagId = tagId
        self.ctrlId = ctrlId
        self.path = path
        self.detail = detail
    }
}

public extension HwpFile {
    /// 문서 전체를 순회해 파서가 해석하지 못한 요소를 집계한다.
    ///
    /// - 결과는 결정적이다. 컨테이너(구역·문단·컨트롤) 순회는 문서 순서를
    ///   따르고, 컨테이너 **안**에서는 종류별 그룹 순서다(unknown record →
    ///   문단/컨트롤 재귀) — 파스가 record를 종류별 배열로 분리하며 원 스트림의
    ///   interleaving 위치를 버리므로 그 이상의 순서는 복원할 수 없다.
    /// - BodyText(`sectionArray`)와 ViewText(`viewSectionArray`)를 모두 본다 —
    ///   렌더 본문 선택(`displaySectionArray`)과 달리, 채택되지 않은 표시본이
    ///   무엇을 담고 있었는지도 진단의 관심사다. 두 본문은 path 접두사
    ///   (`section[i]` / `viewSection[i]`)로 갈린다.
    /// - `.default`와 `.viewer` 로드 결과의 진단은 같다 — unknown record
    ///   payload는 보존 off에서도 비워지지 않고 분리 복사된다 (`HwpUnknownRecord`).
    /// - walker는 자체 깊이 상한을 두지 않는다. 순회할 트리는 파스 시점의
    ///   `HwpReadLimits.maxNestingDepth`가 이미 상한했다 (#64).
    func parseDiagnostics() -> [HwpParseDiagnostic] {
        var collector = HwpParseDiagnosticCollector()
        collector.collect(docInfo: docInfo)
        for (index, section) in sectionArray.enumerated() {
            collector.collect(section: section, path: "section[\(index)]")
        }
        for (index, section) in viewSectionArray.enumerated() {
            collector.collect(section: section, path: "viewSection[\(index)]")
        }
        return collector.diagnostics
    }
}

/// `parseDiagnostics()`의 순회 상태 — path 문자열을 조립하며 진단을 누적한다.
private struct HwpParseDiagnosticCollector {
    var diagnostics = [HwpParseDiagnostic]()
}

// MARK: - unknown record 공통 수집

private extension HwpParseDiagnosticCollector {
    /// record 하나와 그 하위 트리를 보고한다. 하위 record는 트리로 보존되므로
    /// (`HwpUnknownRecord.children`) `.child[i]` 세그먼트로 재귀한다.
    mutating func collect(record: HwpUnknownRecord, path: String) {
        diagnostics.append(
            HwpParseDiagnostic(kind: .unknownRecord, tagId: record.tagId, path: path)
        )
        for (index, child) in record.children.enumerated() {
            collect(record: child, path: "\(path).child[\(index)]")
        }
    }

    mutating func collect(records: [HwpUnknownRecord], segment: String, under path: String) {
        for (index, record) in records.enumerated() {
            collect(record: record, path: "\(path).\(segment)[\(index)]")
        }
    }

    mutating func collectUnknownChildren(_ records: [HwpUnknownRecord], under path: String) {
        collect(records: records, segment: "unknownChild", under: path)
    }

    mutating func collect(ctrlDataRecords: [HwpCtrlData], under path: String) {
        for (index, ctrlData) in ctrlDataRecords.enumerated() {
            collectUnknownChildren(ctrlData.unknownChildren, under: "\(path).ctrlData[\(index)]")
        }
    }
}

// MARK: - DocInfo

private extension HwpParseDiagnosticCollector {
    mutating func collect(docInfo: HwpDocInfo) {
        collect(records: docInfo.unknownRecords, segment: "unknownRecord", under: "docInfo")
        collect(idMappings: docInfo.idMappings)
        if let docData = docInfo.docData {
            for (index, forbiddenChar) in docData.forbiddenCharArray.enumerated() {
                collectUnknownChildren(
                    forbiddenChar.unknownChildren,
                    under: "docInfo.docData.forbiddenChar[\(index)]"
                )
            }
            collectUnknownChildren(docData.unknownChildren, under: "docInfo.docData")
        }
        if let distributeDocData = docInfo.distributeDocData {
            collectUnknownChildren(
                distributeDocData.unknownChildren, under: "docInfo.distributeDocData"
            )
        }
        collect(compatibleDocument: docInfo.compatibleDocument)
        collectTopLevelLayoutCompatibility(docInfo)
        collectTopLevelCombinedRecords(docInfo)
    }

    mutating func collect(idMappings: HwpIdMappings) {
        let path = "docInfo.idMappings"
        collectUnknownChildren(idMappings.unknownChildren, under: path)
        collectRecordChildren(
            idMappings.memoShapeArray.map(\.unknownChildren), segment: "memoShape", under: path
        )
        collectRecordChildren(
            idMappings.trackChangeArray.map(\.unknownChildren), segment: "trackChange", under: path
        )
        collectRecordChildren(
            idMappings.trackChangeContentArray.map(\.unknownChildren),
            segment: "trackChangeContent",
            under: path
        )
        collectRecordChildren(
            idMappings.trackChangeAuthorArray.map(\.unknownChildren),
            segment: "trackChangeAuthor",
            under: path
        )
        collectRecordChildren(
            idMappings.forbiddenCharArray.map(\.unknownChildren),
            segment: "forbiddenChar",
            under: path
        )
    }

    mutating func collect(compatibleDocument: HwpCompatibleDocument?) {
        guard let compatibleDocument else { return }
        let path = "docInfo.compatibleDocument"
        collectUnknownChildren(compatibleDocument.unknownChildren, under: path)
        if let layoutCompatibility = compatibleDocument.layoutCompatibility {
            collectUnknownChildren(
                layoutCompatibility.unknownChildren, under: "\(path).layoutCompatibility"
            )
        }
        collectRecordChildren(
            compatibleDocument.trackChangeArray.map(\.unknownChildren),
            segment: "trackChange",
            under: path
        )
    }

    /// 최상위 LAYOUT_COMPATIBILITY. 최상위 record가 없으면
    /// `docInfo.layoutCompatibility`는 `compatibleDocument` child의 폴백 별칭이라
    /// (HwpDocInfo 파스) 같은 값이면 건너뛰어 이중 보고를 막는다.
    /// `unknownChildren`은 `@ExcludeEquatable`이라 별도로 비교한다.
    mutating func collectTopLevelLayoutCompatibility(_ docInfo: HwpDocInfo) {
        guard let layoutCompatibility = docInfo.layoutCompatibility else { return }
        if let alias = docInfo.compatibleDocument?.layoutCompatibility,
           alias == layoutCompatibility,
           alias.unknownChildren == layoutCompatibility.unknownChildren
        {
            return
        }
        collectUnknownChildren(
            layoutCompatibility.unknownChildren, under: "docInfo.layoutCompatibility"
        )
    }

    /// 결합 배열(idMappings 소유분 + 최상위분 — `HwpDocInfo` 파스가 이 순서로
    /// 이어 붙인다)의 최상위 구간만 걷는다. idMappings 소유분은
    /// `collect(idMappings:)`가 이미 보고했다. path 인덱스는 결합 배열
    /// (`docInfo.memoShapeArray` 등) 기준이라 그대로 조회할 수 있다.
    mutating func collectTopLevelCombinedRecords(_ docInfo: HwpDocInfo) {
        let idMappings = docInfo.idMappings
        collectRecordChildren(
            docInfo.memoShapeArray.map(\.unknownChildren),
            segment: "memoShape",
            under: "docInfo",
            skippingFirst: idMappings.memoShapeArray.count
        )
        collectRecordChildren(
            docInfo.trackChangeArray.map(\.unknownChildren),
            segment: "trackChange",
            under: "docInfo",
            skippingFirst: idMappings.trackChangeArray.count
        )
        collectRecordChildren(
            docInfo.trackChangeContentArray.map(\.unknownChildren),
            segment: "trackChangeContent",
            under: "docInfo",
            skippingFirst: idMappings.trackChangeContentArray.count
        )
        collectRecordChildren(
            docInfo.trackChangeAuthorArray.map(\.unknownChildren),
            segment: "trackChangeAuthor",
            under: "docInfo",
            skippingFirst: idMappings.trackChangeAuthorArray.count
        )
        // forbiddenChar 결합 배열은 idMappings + docData + 최상위 순 —
        // 앞 두 구간은 각자의 소유 경로에서 이미 보고했다.
        let ownedForbiddenCharCount = idMappings.forbiddenCharArray.count
            + (docInfo.docData?.forbiddenCharArray.count ?? 0)
        collectRecordChildren(
            docInfo.forbiddenCharArray.map(\.unknownChildren),
            segment: "forbiddenChar",
            under: "docInfo",
            skippingFirst: ownedForbiddenCharCount
        )
    }

    mutating func collectRecordChildren(
        _ unknownChildrenArray: [[HwpUnknownRecord]],
        segment: String,
        under path: String,
        skippingFirst ownedCount: Int = 0
    ) {
        guard unknownChildrenArray.count > ownedCount else { return }
        for index in ownedCount ..< unknownChildrenArray.count {
            collectUnknownChildren(
                unknownChildrenArray[index], under: "\(path).\(segment)[\(index)]"
            )
        }
    }
}

// MARK: - 구역·문단

private extension HwpParseDiagnosticCollector {
    mutating func collect(section: HwpSection, path: String) {
        if let parseFailure = section.parseFailure {
            diagnostics.append(
                HwpParseDiagnostic(kind: .recoveredSection, path: path, detail: parseFailure)
            )
        }
        collect(records: section.unknownRecords, segment: "unknownRecord", under: path)
        for (index, paragraph) in section.paragraph.enumerated() {
            collect(
                paragraph: paragraph,
                path: "\(path).paragraph[\(index)]",
                isMemoParagraph: false
            )
        }
    }

    mutating func collect(paragraph: HwpParagraph, path: String, isMemoParagraph: Bool) {
        if let parseFailure = paragraph.parseFailure {
            diagnostics.append(HwpParseDiagnostic(
                kind: isMemoParagraph ? .recoveredMemoParagraph : .recoveredParagraph,
                path: path,
                detail: parseFailure
            ))
        }
        collectUnknownChildren(paragraph.unknownChildren, under: path)
        for (index, ctrl) in (paragraph.ctrlHeaderArray ?? []).enumerated() {
            collect(ctrl: ctrl, path: "\(path).ctrl[\(index)]")
        }
        // 메모별 그룹이 경계의 단일 출처다. 그룹 키가 없는 legacy 아카이브만
        // 평탄 배열을 그룹 하나로 간주해 폴백한다 (파스는 둘을 함께 채운다).
        let memoGroups = paragraph.memoParagraphGroups
            ?? paragraph.memoParagraphArray.map { [$0] }
            ?? []
        for (groupIndex, group) in memoGroups.enumerated() {
            for (index, memoParagraph) in group.enumerated() {
                collect(
                    paragraph: memoParagraph,
                    path: "\(path).memo[\(groupIndex)].paragraph[\(index)]",
                    isMemoParagraph: true
                )
            }
        }
    }
}

// MARK: - 컨트롤

private extension HwpParseDiagnosticCollector {
    // HwpCtrlId 스위치는 `default:` 없이 exhaustive로 둔다 — 새 컨트롤 case가
    // 추가되면 컴파일러가 진단 순회 누락을 강제로 잡는다
    // (`HwpUnsupportedDetector.unsupportedHint`와 같은 컨벤션).
    // swiftlint:disable:next cyclomatic_complexity
    mutating func collect(ctrl: HwpCtrlId, path: String) {
        switch ctrl {
        case let .table(table):
            collect(table: table, path: path)
        case let .shape(control), let .line(control), let .rectangle(control),
             let .ellipse(control), let .arc(control), let .polygon(control),
             let .curve(control), let .equation(control), let .equationLegacy(control),
             let .picture(control), let .ole(control), let .container(control):
            collect(shapeControl: control, path: path)
        case let .genShapeObject(object):
            collect(genShapeObject: object, path: path)
        case let .section(sectionDef):
            collectUnknownChildren(sectionDef.unknownChildren, under: path)
        case let .column(column):
            collectUnknownChildren(column.unknownChildren, under: path)
        case let .pageNumberPosition(position):
            collectUnknownChildren(position.unknownChildren, under: path)
        case let .header(control), let .footer(control),
             let .footnote(control), let .endnote(control):
            collect(listControl: control, path: path)
        case let .form(control), let .autoNumber(control), let .newNumber(control),
             let .pageHide(control), let .pageCT(control), let .indexmark(control),
             let .bookmark(control), let .overlapping(control), let .comment(control),
             let .hiddenComment(control), let .other(control):
            collectUnknownChildren(control.unknownChildren, under: path)
            collect(ctrlDataRecords: control.ctrlDataRecords, under: path)
        case let .hyperLink(hyperlink):
            collectUnknownChildren(hyperlink.unknownChildren, under: path)
        case let .memo(control), let .revision(control), let .field(control):
            collectUnknownChildren(control.unknownChildren, under: path)
        case let .notImplemented(header):
            diagnostics.append(
                HwpParseDiagnostic(kind: .notImplementedControl, ctrlId: header.ctrlId, path: path)
            )
            collectUnknownChildren(header.unknownChildren, under: path)
        case let .unknown(header):
            diagnostics.append(
                HwpParseDiagnostic(kind: .unknownControl, ctrlId: header.ctrlId, path: path)
            )
            collectUnknownChildren(header.unknownChildren, under: path)
        }
    }

    mutating func collect(table: HwpTable, path: String) {
        collectUnknownChildren(table.unknownChildren, under: path)
        for (cellIndex, cell) in table.cellArray.enumerated() {
            let cellPath = "\(path).cell[\(cellIndex)]"
            collectUnknownChildren(cell.header.unknownChildren, under: cellPath)
            for (index, paragraph) in cell.paragraphArray.enumerated() {
                collect(
                    paragraph: paragraph,
                    path: "\(cellPath).paragraph[\(index)]",
                    isMemoParagraph: false
                )
            }
        }
    }

    mutating func collect(shapeControl: HwpShapeControl, path: String) {
        collectUnknownChildren(shapeControl.unknownChildren, under: path)
        for (index, component) in shapeControl.shapeComponentArray.enumerated() {
            collect(shapeComponent: component, path: "\(path).shapeComponent[\(index)]")
        }
        // eqEditRecords는 eqEditArray로 typed 파싱된 같은 record의 raw 사본 —
        // 걷지 않는다 (이중 보고 방지). oleRecords도 같은 이유로 component
        // 순회에서 걷지 않는다.
        for (index, eqEdit) in shapeControl.eqEditArray.enumerated() {
            collectUnknownChildren(eqEdit.unknownChildren, under: "\(path).eqEdit[\(index)]")
        }
        collect(ctrlDataRecords: shapeControl.ctrlDataRecords, under: path)
    }

    mutating func collect(genShapeObject: HwpGenShapeObject, path: String) {
        collectUnknownChildren(genShapeObject.unknownChildren, under: path)
        for (index, component) in genShapeObject.shapeComponentArray.enumerated() {
            collect(shapeComponent: component, path: "\(path).shapeComponent[\(index)]")
        }
        collect(ctrlDataRecords: genShapeObject.ctrlDataRecords, under: path)
    }

    /// 리스트 컨트롤 (머리말·꼬리말·각주·미주).
    /// `header.unknownChildren`는 걷지 않는다 — `HwpCtrlHeader.load`가 컨트롤의
    /// **전체** child record(listArray로 typed 소비된 리스트 헤더·문단 포함)를
    /// raw로 담아 두므로, 보고하면 소비된 record가 이중 보고된다.
    mutating func collect(listControl: HwpListControl, path: String) {
        collectUnknownChildren(listControl.unknownChildren, under: path)
        for (index, list) in listControl.listArray.enumerated() {
            collect(listItem: list, path: "\(path).list[\(index)]")
        }
    }

    mutating func collect(listItem: HwpListControlList, path: String) {
        collectUnknownChildren(listItem.headerUnknownChildren, under: path)
        for (index, paragraph) in listItem.paragraphArray.enumerated() {
            collect(
                paragraph: paragraph,
                path: "\(path).paragraph[\(index)]",
                isMemoParagraph: false
            )
        }
    }

    mutating func collect(shapeComponent: HwpShapeComponent, path: String) {
        // 중첩 shape component(컨테이너의 자식 SHAPE_COMPONENT)는 typed 소비
        // 대상이 아니라 unknownChildren에 남으므로 여기 record 재귀가 함께 잡는다.
        collectUnknownChildren(shapeComponent.unknownChildren, under: path)
        collectDetail(shapeComponent.pictureArray.map(\.unknownChildren), "picture", path)
        collectDetail(shapeComponent.lineArray.map(\.unknownChildren), "line", path)
        collectDetail(shapeComponent.rectangleArray.map(\.unknownChildren), "rectangle", path)
        collectDetail(shapeComponent.ellipseArray.map(\.unknownChildren), "ellipse", path)
        collectDetail(shapeComponent.arcArray.map(\.unknownChildren), "arc", path)
        collectDetail(shapeComponent.polygonArray.map(\.unknownChildren), "polygon", path)
        collectDetail(shapeComponent.curveArray.map(\.unknownChildren), "curve", path)
        collectDetail(shapeComponent.oleArray.map(\.unknownChildren), "ole", path)
        collectDetail(shapeComponent.containerArray.map(\.unknownChildren), "container", path)
        collectDetail(shapeComponent.chartDataArray.map(\.unknownChildren), "chartData", path)
        collectDetail(shapeComponent.textartArray.map(\.unknownChildren), "textart", path)
        collectDetail(shapeComponent.formObjectArray.map(\.unknownChildren), "formObject", path)
        collectDetail(shapeComponent.memoShapeArray.map(\.unknownChildren), "memoShape", path)
        collectDetail(shapeComponent.memoListArray.map(\.unknownChildren), "memoList", path)
        collectDetail(shapeComponent.videoDataArray.map(\.unknownChildren), "videoData", path)
        collectDetail(
            shapeComponent.shapeComponentUnknownArray.map(\.unknownChildren),
            "shapeComponentUnknown",
            path
        )
        collect(ctrlDataRecords: shapeComponent.ctrlDataRecords, under: path)
        for (index, textBox) in shapeComponent.textBoxListArray.enumerated() {
            collect(listItem: textBox, path: "\(path).textBox[\(index)]")
        }
    }

    mutating func collectDetail(
        _ unknownChildrenArray: [[HwpUnknownRecord]],
        _ segment: String,
        _ path: String
    ) {
        collectRecordChildren(unknownChildrenArray, segment: segment, under: path)
    }
}

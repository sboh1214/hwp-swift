# HwpKit v1 CoreHwp Coverage Audit

Task T1 audit for HwpKit v1 IN scope. Source was read from `Sources/CoreHwp/HwpFile.swift`, every file under `Sources/CoreHwp/Models/Section/CtrlHeader/**`, every file under `Sources/CoreHwp/Models/DocInfo/IdMappings/**`, and the relevant paragraph/section public models needed to map text and fixture coverage. Fixture inventory is from `find Tests/CoreHwpTests -name "*.hwp"` and fixture manifests.

## v1 IN Feature Coverage

| Feature | CoreHwp Type | Key Properties | Status | Fixture |
| --- | --- | --- | --- | --- |
| text | `HwpFile.sectionArray`, `HwpSection.paragraph`, `HwpParagraph.paraText`, `HwpParaText.charArray`, `HwpChar`; style resolution through `HwpParagraph.paraCharShape.shapeId` and `HwpDocInfo.idMappings.charShapeArray` | `HwpParaText.rawPayload`, `HwpParaText.charArray`, `HwpParaHeader.charCount`, `HwpParaCharShape.startingIndex`, `HwpParaCharShape.shapeId`, `HwpCharShape.faceId`, `HwpCharShape.baseSize`, `HwpCharShape.property.isBold`, `HwpCharShape.property.isItalic`, `HwpCharShape.faceColor`, `HwpFaceName.faceName` | Full for extraction and style IDs; rendering still resolves references in caller | `Tests/CoreHwpTests/Fixtures/plain-text-minimal/document.hwp`, `plain-text-hancom-mac2026/document.hwp`, `CharShape/document.hwp`, `CharShapeProperty/document.hwp`, `noori/document.hwp` |
| paragraph | `HwpParagraph`, `HwpParaHeader`, `HwpParaShape`, `HwpParaLineSeg`, `HwpParaRangeTag`, `HwpStyle` | `HwpParaHeader.paraShapeId`, `paraStyleId`, `columnType`, `controlMask`, `HwpParaShape.marginLeft`, `marginRight`, `indent`, `paragraphSpacingTop`, `paragraphSpacingBottom`, `lineSpacing`, `lineSpacing2`, `tabDefId`, `numberingOrBulletId`, `borderFillId`, `HwpParaLineSeg.paraLineSegInternalArray`, `HwpParaRangeTag.start/end/tag`, `HwpStyle.paraShapeId`, `charShapeId` | Partial: model coverage is broad, but line-seg is a layout cache and may be empty; reference resolution is caller responsibility | `plain-text-hancom-mac2026/document.hwp`, `plain-text-minimal/document.hwp`, `noori/document.hwp`, `Column/document.hwp`, `track-changes/document.hwp` |
| page | `HwpSectionDef`, `HwpPageDef`, `HwpPageBorderFill`, `HwpPageNumberPosition` | `HwpPageDef.width`, `height`, `marginLeft`, `marginRight`, `marginTop`, `marginBottom`, `marginHeader`, `marginFootnote`, `marginGutter`, `HwpPageBorderFill.spacingLeft/Right/Top/Bottom`, `borderFillId`, `HwpPageNumberPosition.propertyInfo.numberFormat`, `displayPosition`, `headDecoration`, `tailDecoration` | Partial: page dimensions/margins/page-number are typed; some property bits and page border fill semantics remain raw/trailing | `noori/document.hwp`, `Column/document.hwp`, `2007/document.hwp`, blank fixtures |
| section | `HwpFile.sectionArray`, `HwpSection`, `HwpSectionDef`, `HwpSectionDefProperty`, `HwpColumn` | `HwpSection.paragraph`, `unknownRecords`, `HwpSectionDef.pageDef`, `footNoteShape`, `endNoteShape`, `propertyInfo.hideHeader`, `hideFooter`, `textDirectionRawValue`, `columnSpacing`, `defaultTabSpacing`, `pageStartNumber`, `HwpColumn.property.count`, `property.direction`, `spacing`, `widthArray`, `gapArray` | Partial: sections, section-def, columns are parsed; version-specific/unknown tails are preserved raw | `multi-section/document.hwp`, `Column/document.hwp`, `legacy-common-control-property/document.hwp`, `noori/document.hwp` |
| table | `HwpCtrlId.table(HwpTable)`, `HwpTable`, `HwpTableProperty`, `HwpTableCell`, `HwpTableCellHeader`, `HwpTableCellHeaderProperty`, `HwpZoneProperty` | `HwpTable.commonCtrlProperty`, `tableProperty.rowCount`, `columnCount`, `cellSpacing`, `leftInnerMargin`, `rightInnerMargin`, `topInnerMargin`, `bottomInnerMargin`, `rowSize`, `borderFillId`, `zonePropertyArray`, `cellArray`, `HwpTableCell.header.paragraphCount`, `paragraphArray`, `isHeader` | Partial: table/grid/cell paragraphs are typed; cell geometry/border references need caller resolution and some cell/header trailing payload is raw-preserved | `noori/document.hwp`, `legacy-common-control-property/document.hwp`, `track-changes/document.hwp` |
| image | `HwpCtrlId.picture(HwpShapeControl)`, `HwpShapeComponentPicture`, `HwpBinData`, `HwpBinaryData`, `HwpCommonCtrlProperty` | `HwpShapeControl.commonCtrlProperty`, `shapeComponentArray`, `HwpShapeComponent.pictureArray`, `HwpShapeComponentPicture.binaryDataId`, `rawPayload`, `rawTrailing`, `HwpBinData.streamId`, `extensionName`, `property.type`, `property.compressType`, `HwpFile.binaryDataArray` | Partial / Raw-only: BinData metadata and payload are exposed; picture component only best-effort extracts BinData id and preserves most details as raw payload | `BinData/document.hwp`, `noori/document.hwp`, `CCL/document.hwp`, `공공누리/document.hwp`, `chart/document.hwp` |
| footnote | `HwpCtrlId.footnote(HwpListControl)`, `HwpCtrlId.endnote(HwpListControl)`, `HwpListControl`, `HwpListControlList`, `HwpFootnoteShape` | `HwpListControl.listArray`, `HwpListControlList.header.paragraphCount`, `paragraphArray`, `HwpSectionDef.footNoteShape`, `endNoteShape`, `HwpFootnoteShape.startingNumber`, `dividerLength`, `dividerMarginTop`, `dividerMarginBottom`, `marginComment`, `dividerType`, `dividerThickness`, `dividerColor` | Partial: nested footnote/endnote text is parsed; note placement/layout details and unknown list children are raw-preserved | `footnote-endnote/document.hwp`, `track-changes/document.hwp`, `legacy-common-control-property/document.hwp` |
| shape | `HwpCtrlId.line/rectangle/ellipse/arc/polygon/curve/shape/genShapeObject`, `HwpShapeControl`, `HwpGenShapeObject`, `HwpShapeComponent`, raw-backed component detail types | `HwpCommonCtrlProperty.propertyInfo.treatAsChar`, `verticalOffset`, `horizontalOffset`, `width`, `height`, `zOrder`, `marginArray`, `instanceId`, `objectDescription`, `HwpShapeComponent.rawCtrlId`, `ctrlId`, `lineArray`, `rectangleArray`, `ellipseArray`, `polygonArray`, `curveArray`, `oleArray`, `ctrlDataRecords`, `unknownChildren` | Raw-only / Partial: common object placement is typed, but most component geometry is raw-backed; shape line/rectangle detail does not expose rotation/path geometry | `legacy-common-control-property/document.hwp`, `text-box/document.hwp`, `CCL/document.hwp`, `공공누리/document.hwp`, `chart/document.hwp` |
| textbox | `HwpCtrlId.genShapeObject(HwpGenShapeObject)`, `HwpShapeComponent.textBoxListArray`, `HwpListControlList`, nested `HwpParagraph` | `HwpGenShapeObject.commonCtrlProperty`, `shapeComponentArray`, `HwpShapeComponent.rectangleArray`, `textBoxListArray`, `HwpListControlList.header`, `paragraphArray`, nested `HwpParaText.charArray` | Partial: non-floating text-box content and common shape placement are available; rectangle/detail payload remains raw | `text-box/document.hwp` |
| hyperlink | `HwpCtrlId.hyperLink(HwpHyperlink)`, fallback `HwpFieldControl` | `HwpHyperlink.property`, `unknownPrefix`, `urlLength`, `url`, `urlRawPayload`, `rawTrailing`, `unknownChildren`; fallback `HwpFieldControl.command`, `fieldParameter`, `fieldParameterRawPayload` | Partial: URL is typed; field property semantics and trailing bytes are raw-preserved | `CCL/document.hwp`, `공공누리/document.hwp` |

## `HwpCtrlId.notImplemented` / `.unknown` Occurrences

Grep patterns: `notImplemented` and `\.unknown\(` in `Sources/CoreHwp/`.

| Kind | file:line | Occurrence |
| --- | --- | --- |
| enum case | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:42` | `case notImplemented(HwpCtrlHeader)` |
| coding key | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:57` | `case notImplemented, unknown` |
| decode | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:184-186` | Decodes `.notImplemented(HwpCtrlHeader)` |
| encode | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:270-271` | Encodes `.notImplemented(HwpCtrlHeader)` |
| fallback | `Sources/CoreHwp/Models/Section/HwpParagraph.swift:250` | `genShapeObjectOrNotImplemented` raw fallback |
| fallback | `Sources/CoreHwp/Models/Section/HwpParagraph.swift:267` | common shape control raw fallback |
| fallback | `Sources/CoreHwp/Models/Section/HwpParagraph.swift:310` | table raw fallback |
| decode | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:189` | `self = .unknown(hwpCtrlHeader)` |
| encode | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:272` | `case let .unknown(hwpCtrlHeader)` |
| unknown control dispatch | `Sources/CoreHwp/Models/Section/HwpParagraph.swift:123` | `return .unknown(header)` for unmapped ctrl id |

Note: grep also matched explanatory `AGENTS.md` lines under `Sources/CoreHwp/`; the table above lists Swift implementation occurrences only.

## TODO / FIXME in `Sources/CoreHwp/`

Grep patterns: `TODO|FIXME` in `Sources/CoreHwp/**/*.swift`.

| file:line | Text |
| --- | --- |
| none | No `TODO` or `FIXME` occurrences were found in Swift files under `Sources/CoreHwp/` during this audit. |

## Fixture Inventory Categorized by v1 IN Feature

Inventory source: `find Tests/CoreHwpTests -name "*.hwp"` (33 files) and fixture `features` manifests.

| Fixture `.hwp` | v1 IN category exercised | Manifest feature tags / note |
| --- | --- | --- |
| `Tests/CoreHwpTests/Fixtures/2007/document.hwp` | page, section, paragraph | `version`, `doc-info`, `doc-properties`, `preview-text`, `preview-image`, `missing-bin-data`; includes section/page baseline fields |
| `Tests/CoreHwpTests/Fixtures/2014VP/document.hwp` | page, section, paragraph | `version`, `doc-info`, `doc-properties`, preview streams |
| `Tests/CoreHwpTests/Fixtures/BinData/document.hwp` | image | `bin-data`, `embedded-image-reference`, `preview-image` |
| `Tests/CoreHwpTests/Fixtures/CCL/document.hwp` | text, paragraph, image, shape, hyperlink | `paragraph-text`, `hyperlink`, `shape-object`, `bin-data` |
| `Tests/CoreHwpTests/Fixtures/CharShape/document.hwp` | text | `char-shape` DocInfo mapping coverage |
| `Tests/CoreHwpTests/Fixtures/CharShapeProperty/document.hwp` | text | `char-shape-property` DocInfo mapping coverage |
| `Tests/CoreHwpTests/Fixtures/Column/document.hwp` | section, page, paragraph | `section`, `columns`, `doc-properties` |
| `Tests/CoreHwpTests/Fixtures/blank-mac2014vp/document.hwp` | page, section, paragraph baseline | `blank`, `doc-info`, `doc-properties`, preview streams |
| `Tests/CoreHwpTests/Fixtures/blank-win2018/document.hwp` | page, section, paragraph baseline | `blank`, `doc-info`, `doc-properties`, preview streams |
| `Tests/CoreHwpTests/Fixtures/blank-win2020/document.hwp` | page, section, paragraph baseline | `blank`, `doc-info`, `doc-properties`, preview streams |
| `Tests/CoreHwpTests/Fixtures/bookmark/document.hwp` | text, paragraph | `bookmark`, `paragraph-text`; adjacent control coverage but bookmark is out of v1 list |
| `Tests/CoreHwpTests/Fixtures/chart/document.hwp` | text, paragraph, image, shape | `chart`, `paragraph-text`, `image`, `bin-data`; chart itself is v1 OUT placeholder, but image/shape plumbing is exercised |
| `Tests/CoreHwpTests/Fixtures/drm-unsupported-derived/document.hwp` | none of v1 render features | `drm`, `unsupported`, `derived-drm`; parser rejection path only |
| `Tests/CoreHwpTests/Fixtures/equation/document.hwp` | text, paragraph, shape | `equation`, `paragraph-text`; equation is v1 OUT placeholder but shape control path is exercised |
| `Tests/CoreHwpTests/Fixtures/footnote-endnote/document.hwp` | text, paragraph, footnote | `footnote-endnote`, `paragraph-text` |
| `Tests/CoreHwpTests/Fixtures/header-footer/document.hwp` | text, paragraph, page/section list controls | `header-footer`, `paragraph-text`; header/footer are not named in v1 list but share `HwpListControl` with footnote/endnote |
| `Tests/CoreHwpTests/Fixtures/legacy-common-control-property/document.hwp` | section, table, image, shape, footnote | `large-document`, `multi-section`, `shape-object`, `other-controls`, `bin-data`; manifest counts include tables and many footnote controls |
| `Tests/CoreHwpTests/Fixtures/memo/document.hwp` | text, paragraph | `memo`, `paragraph-text`; memo itself is not v1 IN but field-control parser is exercised |
| `Tests/CoreHwpTests/Fixtures/missing-preview-image-derived/document.hwp` | text, paragraph | `plain-text-minimal`, `paragraph-text`, `derived-missing-preview-image` |
| `Tests/CoreHwpTests/Fixtures/missing-preview-text-derived/document.hwp` | text, paragraph | `plain-text-minimal`, `paragraph-text`, optional preview mutation |
| `Tests/CoreHwpTests/Fixtures/missing-summary-derived/document.hwp` | text, paragraph | `plain-text-minimal`, `paragraph-text`, optional summary mutation |
| `Tests/CoreHwpTests/Fixtures/multi-section/document.hwp` | text, paragraph, section | `multi-section`, `paragraph-text`, `memo-shape` |
| `Tests/CoreHwpTests/Fixtures/noori/document.hwp` | text, paragraph, page, section, table, image, shape, hyperlink-adjacent DocInfo | `paragraph-text`, `multi-paragraph`, `table`, `image`, `shape-object`, `columns`, `page-number`, `bin-data`, `styles`, `bullets-numbering` |
| `Tests/CoreHwpTests/Fixtures/plain-text-hancom-mac2026/document.hwp` | text, paragraph, page/section baseline | `paragraph-text`, `multi-paragraph` |
| `Tests/CoreHwpTests/Fixtures/plain-text-minimal/document.hwp` | text, paragraph, page/section baseline | `plain-text-minimal`, `paragraph-text`, ignored root entries |
| `Tests/CoreHwpTests/Fixtures/text-box/document.hwp` | textbox, shape, text, paragraph | `text-box`, `shape-object`, `missing-bin-data` |
| `Tests/CoreHwpTests/Fixtures/track-changes/document.hwp` | text, paragraph, table/image counters, footnote/endnote counters | `track-changes`, `paragraph-text`, DocInfo raw records; manifest has control counts for footnote/endnote/picture/table |
| `Tests/CoreHwpTests/Fixtures/공공누리/document.hwp` | text, paragraph, image, shape, hyperlink | `kogl`, `paragraph-text`, `hyperlink`, `shape-object`, `bin-data` |
| `Tests/CoreHwpTests/Fixtures/문서암호설정-보안수준높음/document.hwp` | none of v1 render features | `encrypted`, `unsupported` |
| `Tests/CoreHwpTests/Fixtures/문서암호설정-보안수준보통/document.hwp` | none of v1 render features | `encrypted`, `unsupported` |
| `Tests/CoreHwpTests/Fixtures/문서이력관리/document.hwp` | page/section metadata | `document-history`, `doc-info`, `doc-properties`, preview streams |
| `Tests/CoreHwpTests/Fixtures/배포용문서/document.hwp` | none of v1 render features | `deployment-document`, `unsupported` |
| `Tests/CoreHwpTests/Fixtures/변경내용추적/document.hwp` | page/section metadata | `track-changes-flag`, `doc-info`, `doc-properties`; legacy flag fixture, not actual tracked body changes |

## Status Summary

| Status | v1 IN features |
| --- | --- |
| Full | text extraction/style IDs |
| Partial | paragraph, page, section, table, image, footnote, textbox, hyperlink |
| Raw-only / Partial | shape component geometry/detail records |
| Absent | none found for the 10 requested v1 IN features |

## Scope Reduction Recommendation

No v1 IN feature has zero CoreHwp coverage. However, renderer scope should treat **shape** and **image** as raw-backed/placeholder-heavy: CoreHwp exposes placement (`HwpCommonCtrlProperty`) and binary references, but most shape component geometry and picture component detail beyond BinData id are raw payload. If HwpKit v1 requires faithful arbitrary shape drawing, trim to “basic placeholder/box with known bounds” unless CoreHwp models are expanded in a later task.

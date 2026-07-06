# HwpKit v1 CoreHwp Coverage Audit

Task T1 audit for HwpKit v1 IN scope. Source was read from `Sources/CoreHwp/HwpFile.swift`, every file under `Sources/CoreHwp/Models/Section/CtrlHeader/**`, every file under `Sources/CoreHwp/Models/DocInfo/IdMappings/**`, and the relevant paragraph/section public models needed to map text and fixture coverage. Fixture inventory is from `find Tests/CoreHwpTests -name "*.hwp"` and fixture manifests.

## v1 IN Feature Coverage

| Feature | CoreHwp Type | Key Properties | Status | Fixture |
| --- | --- | --- | --- | --- |
| text | `HwpFile.sectionArray`, `HwpSection.paragraph`, `HwpParagraph.paraText`, `HwpParaText.charArray`, `HwpChar`; style resolution through `HwpParagraph.paraCharShape.shapeId` and `HwpDocInfo.idMappings.charShapeArray` | `HwpParaText.rawPayload`, `HwpParaText.charArray`, `HwpParaHeader.charCount`, `HwpParaCharShape.startingIndex`, `HwpParaCharShape.shapeId`, `HwpCharShape.faceId`, `HwpCharShape.baseSize`, `HwpCharShape.property.isBold`, `HwpCharShape.property.isItalic`, `HwpCharShape.faceColor`, `HwpFaceName.faceName` | Full for extraction and style IDs; rendering still resolves references in caller | `Tests/CoreHwpTests/Fixtures/plain-text-minimal/document.hwp`, `plain-text-hancom-mac2026/document.hwp`, `CharShape/document.hwp`, `CharShapeProperty/document.hwp`, `noori/document.hwp` |
| paragraph | `HwpParagraph`, `HwpParaHeader`, `HwpParaShape`, `HwpParaLineSeg`, `HwpParaRangeTag`, `HwpStyle` | `HwpParaHeader.paraShapeId`, `paraStyleId`, `columnType`, `controlMask`, `HwpParaShape.marginLeft`, `marginRight`, `indent`, `paragraphSpacingTop`, `paragraphSpacingBottom`, `lineSpacing`, `lineSpacing2`, `tabDefId`, `numberingOrBulletId`, `borderFillId`, `HwpParaLineSeg.paraLineSegInternalArray`, `HwpParaRangeTag.start/end/tag`, `HwpStyle.paraShapeId`, `charShapeId` | Partial: model coverage is broad, but line-seg is a layout cache and may be empty; reference resolution is caller responsibility | `plain-text-hancom-mac2026/document.hwp`, `plain-text-minimal/document.hwp`, `noori/document.hwp`, `Column/document.hwp`, `track-changes/document.hwp` |
| page | `HwpSectionDef`, `HwpPageDef`, `HwpPageBorderFill`, `HwpPageNumberPosition` | `HwpPageDef.width`, `height`, `marginLeft`, `marginRight`, `marginTop`, `marginBottom`, `marginHeader`, `marginFootnote`, `marginGutter`, `HwpPageBorderFill.spacingLeft/Right/Top/Bottom`, `borderFillId`, `HwpPageNumberPosition.propertyInfo.numberFormat`, `displayPosition`, `headDecoration`, `tailDecoration` | Partial: page dimensions/margins/page-number are typed; some property bits and page border fill semantics remain raw/trailing | `noori/document.hwp`, `Column/document.hwp`, `2007/document.hwp`, blank fixtures |
| section | `HwpFile.sectionArray`, `HwpSection`, `HwpSectionDef`, `HwpSectionDefProperty`, `HwpColumn` | `HwpSection.paragraph`, `unknownRecords`, `HwpSectionDef.pageDef`, `footNoteShape`, `endNoteShape`, `propertyInfo.hideHeader`, `hideFooter`, `textDirectionRawValue`, `columnSpacing`, `defaultTabSpacing`, `pageStartNumber`, `HwpColumn.property.count`, `property.direction`, `spacing`, `widthArray`, `gapArray` | Partial: sections, section-def, columns are parsed; version-specific/unknown tails are preserved raw | `multi-section/document.hwp`, `Column/document.hwp`, `legacy-common-control-property/document.hwp`, `noori/document.hwp` |
| table | `HwpCtrlId.table(HwpTable)`, `HwpTable`, `HwpTableProperty`, `HwpTableCell`, `HwpTableCellHeader`, `HwpTableCellHeaderProperty`, `HwpZoneProperty` | `HwpTable.commonCtrlProperty`, `tableProperty.rowCount`, `columnCount`, `cellSpacing`, `leftInnerMargin`, `rightInnerMargin`, `topInnerMargin`, `bottomInnerMargin`, `rowSize`, `borderFillId`, `zonePropertyArray`, `cellArray`, `HwpTableCell.header.paragraphCount`, `paragraphArray`, `isHeader` | Full for layout: cell geometry (`HwpTableCellHeader.cellProperty` — 표 80: address/span/width/height/margins/borderFillId), row cell counts (`rowCellCounts`), page-break bits (`pageBreakMode`) are decoded; zone/trailing tails remain raw-preserved | `noori/document.hwp`, `legacy-common-control-property/document.hwp`, `track-changes/document.hwp` |
| image | `HwpCtrlId.picture(HwpShapeControl)`, `HwpShapeComponentPicture`, `HwpBinData`, `HwpBinaryData`, `HwpCommonCtrlProperty` | `HwpShapeControl.commonCtrlProperty`, `shapeComponentArray`, `HwpShapeComponent.pictureArray`, `HwpShapeComponentPicture.binaryDataId`, `rawPayload`, `rawTrailing`, `HwpBinData.streamId`, `extensionName`, `property.type`, `property.compressType`, `HwpFile.binaryDataArray` | Full for rendering: `HwpShapeComponentPicture.pictureProperty` decodes 표 107 (border, image corners, crop, inner margins, brightness/contrast/effect, binItemId); `HwpImageStore` joins binItemId → decompressed bytes; stream names parse as hex (BIN%04X) | `BinData/document.hwp`, `noori/document.hwp`, `CCL/document.hwp`, `공공누리/document.hwp`, `chart/document.hwp` |
| footnote | `HwpCtrlId.footnote(HwpListControl)`, `HwpCtrlId.endnote(HwpListControl)`, `HwpListControl`, `HwpListControlList`, `HwpFootnoteShape` | `HwpListControl.listArray`, `HwpListControlList.header.paragraphCount`, `paragraphArray`, `HwpSectionDef.footNoteShape`, `endNoteShape`, `HwpFootnoteShape.startingNumber`, `dividerLength`, `dividerMarginTop`, `dividerMarginBottom`, `marginComment`, `dividerType`, `dividerThickness`, `dividerColor` | Full for layout: divider geometry decoded tolerantly (`HwpFootnoteShape.dividerInfo` — 2/4-byte length variants), numbering mode bits exposed; unknown list children raw-preserved | `footnote-endnote/document.hwp`, `track-changes/document.hwp`, `legacy-common-control-property/document.hwp` |
| shape | `HwpCtrlId.line/rectangle/ellipse/arc/polygon/curve/shape/genShapeObject`, `HwpShapeControl`, `HwpGenShapeObject`, `HwpShapeComponent`, raw-backed component detail types | `HwpCommonCtrlProperty.propertyInfo.treatAsChar`, `verticalOffset`, `horizontalOffset`, `width`, `height`, `zOrder`, `marginArray`, `instanceId`, `objectDescription`, `HwpShapeComponent.rawCtrlId`, `ctrlId`, `lineArray`, `rectangleArray`, `ellipseArray`, `polygonArray`, `curveArray`, `oleArray`, `ctrlDataRecords`, `unknownChildren` | Decoded for rendering: `HwpShapeComponent.detail` (표 83 element props + 표 84 matrices + 표 86 border line + 표 28 fill) and per-kind details (`lineDetail`/`rectangleDetail`/`ellipseDetail`/`arcDetail`/`polygonDetail`/`curveDetail`) are decoded; TEXTART/FORM/CHART details remain raw | `legacy-common-control-property/document.hwp`, `text-box/document.hwp`, `CCL/document.hwp`, `공공누리/document.hwp`, `chart/document.hwp` |
| textbox | `HwpCtrlId.genShapeObject(HwpGenShapeObject)`, `HwpShapeComponent.textBoxListArray`, `HwpListControlList`, nested `HwpParagraph` | `HwpGenShapeObject.commonCtrlProperty`, `shapeComponentArray`, `HwpShapeComponent.rectangleArray`, `textBoxListArray`, `HwpListControlList.header`, `paragraphArray`, nested `HwpParaText.charArray` | Full for layout: text-box paragraphs + 표 90 text margins (`HwpListControlList.textBoxInfo`) + border/fill from component detail are decoded | `text-box/document.hwp` |
| hyperlink | `HwpCtrlId.hyperLink(HwpHyperlink)`, fallback `HwpFieldControl` | `HwpHyperlink.property`, `unknownPrefix`, `urlLength`, `url`, `urlRawPayload`, `rawTrailing`, `unknownChildren`; fallback `HwpFieldControl.command`, `fieldParameter`, `fieldParameterRawPayload` | Partial: URL is typed; field property semantics and trailing bytes are raw-preserved | `CCL/document.hwp`, `공공누리/document.hwp` |

## `HwpCtrlId.notImplemented` / `.unknown` Occurrences

Grep patterns: `notImplemented` and `\.unknown\(` in `Sources/CoreHwp/`.

| Kind | file:line | Occurrence |
| --- | --- | --- |
| enum case | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:42` | `case notImplemented(HwpCtrlHeader)` |
| coding key | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:57` | `case notImplemented, unknown` |
| decode | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:184-186` | Decodes `.notImplemented(HwpCtrlHeader)` |
| encode | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:270-271` | Encodes `.notImplemented(HwpCtrlHeader)` |
| fallback | `Sources/CoreHwp/Models/Section/HwpParagraph.swift:258` | `genShapeObjectOrNotImplemented` raw fallback |
| fallback | `Sources/CoreHwp/Models/Section/HwpParagraph.swift:275` | common shape control raw fallback |
| fallback | `Sources/CoreHwp/Models/Section/HwpParagraph.swift:318` | table raw fallback |
| decode | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:189` | `self = .unknown(hwpCtrlHeader)` |
| encode | `Sources/CoreHwp/Enums/CtrlId/HwpCtrlId.swift:272` | `case let .unknown(hwpCtrlHeader)` |
| unknown control dispatch | `Sources/CoreHwp/Models/Section/HwpParagraph.swift:131` | `return .unknown(header)` for unmapped ctrl id |

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
| Full | text extraction/style IDs, table cell geometry, picture property/BinData join, textbox margins, footnote divider, shape component geometry (line/rect/ellipse/arc/polygon/curve) |
| Partial | paragraph, page, section (columns unwired), hyperlink |
| Raw-only | TEXTART/FORM_OBJECT/CHART_DATA component details |
| Absent | none found for the 10 requested v1 IN features |

## Scope Reduction Recommendation

(2026-07 갱신 3차) 표/글상자/각주/도형/이미지에 이어 다단(`cold`) 밴드
레이아웃(균형 배분 포함), 줄 중간(treat-as-char) 앵커, 미주 문서/구역 끝
배치(표 134 bits 8-9), 머리말/꼬리말 페이지 반복(표 141 적용 범위), 중첩 표
재귀(깊이 3)와 페이지 초과 row 분할, 각주 페이지 귀속·이월, 그림
crop/밝기/명암/효과(표 107) 렌더까지 연결되었다.

한/글 2007 계열 실저장본(대한민국헌법주석) 대비 정합 작업으로 다음이
추가되었다: PARA_LINE_SEG 절대 lineLocation 정규화(문단-상대 높이), 줄 간격
종류 해석(표 44 bit 0-1/표 46 bit 0-4 — 비율%는 글자 크기 기준, 속성3 우선),
각주/미주 참조 위 첨자 번호와 각주 문단 자동 번호(atno, 표 142/143) 치환,
새 번호 지정(nwno, 표 144)의 쪽/각주/미주 카운터 재설정, 쪽 번호
위치(표 147/148)와 쪽 감추기(표 145) 렌더, 문단 쪽 나누기(문단 헤더
columnType bit 2), 한국어 서체 폴백 확장(휴먼명조·신명·한양·한컴바탕·윤고딕
계열 + `-`/`#` 접두·공백 정규화). CoreHwp에는 `HwpOtherControl`의
autoNumberInfo/newNumberInfo typed payload와 `HwpParaShape`의
resolvedLineSpacingKind/Value, `HwpLineSpacingKind`가 추가되었다.

(2026-07-06 갱신 4차 — PrvImage fidelity 작업) 픽스처 내장 PrvImage(한컴
렌더 기준)와의 잉크 밀도 자동 대조로 다음이 정합되었다: 본문 프레임의
머리말/꼬리말 영역 예약(본문 상단 = 위 여백+머리말 여백), 라인 캐시 run
기반 다단 텍스트 배분(비등폭 단은 글자 위치 비례), 단 정의 밴드 간
줄 간격, 글자처럼 취급 표의 앵커 줄 인라인 배치, 각주 스택·표 셀 높이의
라인 캐시 우선 측정(같은 각주 컨트롤 문단은 간격 0), 절대 캐시 문단의
하단 줄 간격 몫 절단. 렌더 페이지 수는 manifest `expectations.pageCount`로
잠근다 (헌법주석 계열 1,031 — 한글 인쇄본 1,030 대비 +1, AGENTS.md 한계).

남은 자발적 축소 범위: 수식(`eqed`) 스크립트 렌더 (placeholder 유지),
TEXTART/FORM_OBJECT/CHART_DATA 세부 디코딩, 그림 PATTERN8x8 효과,
단 나누기(columnType bit 3)/홀·짝수 조정(pageCT), 표 셀 안 각주 참조
위 첨자, 번호 모양 0x80/0x81 사용자 문자, 양쪽 정렬의 단어-간격-우선
justification (CT 공개 API 부재 — 좁은 단 자간 차이).

## PrvImage Fidelity 하네스 (Tests/HwpKitTests)

각 HWP에 내장된 PrvImage(한컴오피스가 저장 시 직접 렌더한 1페이지
미리보기)를 한글.app 렌더의 기준 이미지로 사용하는 자동 회귀 스위트.

```bash
swift test --filter FixturePreviewFidelityTests   # 전 픽스처 fidelity 게이트
```

- `FixturePreviewSupport.swift` — 렌더/비교 유틸: `FixturePreview.firstPage`
  (1페이지만 lazy 페이지네이션), `renderImage` (HwpPageLayer 실제 draw 경로,
  이미지 참조 사전 디코딩, zoom 크롭 지원), `inkGrid` (그레이스케일 N×M 셀
  평균 잉크), `scaleMatchedError` (최소제곱 스칼라 s ∈ [1/3, 3]로 폰트
  대체/AA 강도 차를 제거한 MAE).
- `FixturePreviewFidelityTests.swift` — 픽스처별 임계 테이블 (실측 + 여유,
  근거 주석). 테스트 실행 시 전 픽스처의 실측 리포트(MAE/raw/ink scale)를
  출력한다. 새 픽스처는 실측 후 임계 엔트리를 추가해야 통과한다.
  파싱 불가 4종(암호 2·배포용·drm)과 PrvImage 없는 1종은 명시적 제외·검증.
- BinData 픽스처의 PrvImage는 페이지 좌상단 1/4의 2× 렌더라 zoom 보정으로
  대조한다 (`previewZoomOverrides`).
- 진단 시 렌더/PrvImage 나란히 PNG 덤프는 `FixturePreview` 유틸로 스크래치
  테스트를 만들어 사용한다 (커밋 금지 — repo에는 이미지 산출물을 두지 않는다).
- 페이지 수 회귀 가드: manifest `expectations.pageCount`(+`pageCountSource`)
  ↔ `FixtureRenderTests.testPageCountsMatchManifest`.

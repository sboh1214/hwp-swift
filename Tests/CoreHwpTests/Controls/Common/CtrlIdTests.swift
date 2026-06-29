// swiftlint:disable file_length
@testable import CoreHwp
import Foundation
import Nimble
import XCTest

private func makeCtrlId(_ string: String) -> UInt32 {
    expect(string.count) == 4
    let array = string.asciiValues.map { UInt32($0) }
    guard array.count == 4 else {
        return 0
    }
    return (array[0] << 24) + (array[1] << 16) + (array[2] << 8) + array[3]
}

final class CtrlIdTests: XCTestCase {
    func testCommonCtrlId() {
        expect(HwpCommonCtrlId.table.rawValue) == makeCtrlId("tbl ")

        expect(HwpCommonCtrlId.line.rawValue) == makeCtrlId("$lin")
        expect(HwpCommonCtrlId.rectangle.rawValue) == makeCtrlId("$rec")
        expect(HwpCommonCtrlId.ellipse.rawValue) == makeCtrlId("$ell")
        expect(HwpCommonCtrlId.arc.rawValue) == makeCtrlId("$arc")
        expect(HwpCommonCtrlId.polygon.rawValue) == makeCtrlId("$pol")
        expect(HwpCommonCtrlId.curve.rawValue) == makeCtrlId("$cur")

        expect(HwpCommonCtrlId.equation.rawValue) == makeCtrlId("eqed")
        expect(HwpCommonCtrlId.equationLegacy.rawValue) == makeCtrlId("equd")
        expect(HwpCommonCtrlId.picture.rawValue) == makeCtrlId("$pic")
        expect(HwpCommonCtrlId.ole.rawValue) == makeCtrlId("$ole")
        expect(HwpCommonCtrlId.container.rawValue) == makeCtrlId("$con")

        expect(HwpCommonCtrlId.genShapeObject.rawValue) == makeCtrlId("gso ")
    }

    func testKnownCommonControlIdsHaveSemanticCtrlIdCases() throws {
        let casesById = Dictionary(uniqueKeysWithValues: try semanticCommonControlIds().map {
            ($0.id, $0.name)
        })

        expect(Set(casesById.keys)) == Set(HwpCommonCtrlId.allCases)
        for ctrlId in HwpCommonCtrlId.allCases {
            expect(casesById[ctrlId]) == String(describing: ctrlId)
        }
    }

    func testOtherCtrlID() {
        expect(HwpOtherCtrlId.section.rawValue) == makeCtrlId("secd")
        expect(HwpOtherCtrlId.column.rawValue) == makeCtrlId("cold")
        expect(HwpOtherCtrlId.header.rawValue) == makeCtrlId("head")
        expect(HwpOtherCtrlId.footer.rawValue) == makeCtrlId("foot")
        expect(HwpOtherCtrlId.footnote.rawValue) == makeCtrlId("fn  ")
        expect(HwpOtherCtrlId.endnote.rawValue) == makeCtrlId("en  ")
        expect(HwpOtherCtrlId.form.rawValue) == makeCtrlId("form")
        expect(HwpOtherCtrlId.autoNumber.rawValue) == makeCtrlId("atno")
        expect(HwpOtherCtrlId.newNumber.rawValue) == makeCtrlId("nwno")
        expect(HwpOtherCtrlId.pageHide.rawValue) == makeCtrlId("pghd")
        expect(HwpOtherCtrlId.pageCT.rawValue) == makeCtrlId("pgct")
        expect(HwpOtherCtrlId.pageNumberPosition.rawValue) == makeCtrlId("pgnp")
        expect(HwpOtherCtrlId.indexmark.rawValue) == makeCtrlId("idxm")
        expect(HwpOtherCtrlId.bookmark.rawValue) == makeCtrlId("bokm")
        expect(HwpOtherCtrlId.overlapping.rawValue) == makeCtrlId("tcps")
        expect(HwpOtherCtrlId.comment.rawValue) == makeCtrlId("tdut")
        expect(HwpOtherCtrlId.hiddenComment.rawValue) == makeCtrlId("tcmt")
    }

    func testKnownOtherControlIdsHaveSemanticCtrlIdCases() {
        let casesById = Dictionary(uniqueKeysWithValues: semanticOtherControlIds().map {
            ($0.id, $0.name)
        })

        expect(Set(casesById.keys)) == Set(HwpOtherCtrlId.allCases)
        for ctrlId in HwpOtherCtrlId.allCases {
            expect(casesById[ctrlId]) == String(describing: ctrlId)
        }
    }

    func testFieldCtrlId() {
        expect(HwpFieldCtrlId.unknown.rawValue) == makeCtrlId("%unk")
        expect(HwpFieldCtrlId.date.rawValue) == makeCtrlId("$dte")
        expect(HwpFieldCtrlId.docDate.rawValue) == makeCtrlId("%ddt")
        expect(HwpFieldCtrlId.path.rawValue) == makeCtrlId("%pat")
        expect(HwpFieldCtrlId.bookmark.rawValue) == makeCtrlId("%bmk")
        expect(HwpFieldCtrlId.mailMerge.rawValue) == makeCtrlId("%mmg")
        expect(HwpFieldCtrlId.crossRef.rawValue) == makeCtrlId("%xrf")
        expect(HwpFieldCtrlId.formula.rawValue) == makeCtrlId("%fmu")
        expect(HwpFieldCtrlId.clickHere.rawValue) == makeCtrlId("%clk")
        expect(HwpFieldCtrlId.summary.rawValue) == makeCtrlId("%smr")
        expect(HwpFieldCtrlId.userInfo.rawValue) == makeCtrlId("%usr")
        expect(HwpFieldCtrlId.hyperLink.rawValue) == makeCtrlId("%hlk")

        expect(HwpFieldCtrlId.revisionSign.rawValue) == makeCtrlId("%sig")
        expect(HwpFieldCtrlId.revisionDelete.rawValue) == makeCtrlId("%%*d")
        expect(HwpFieldCtrlId.revisionAttach.rawValue) == makeCtrlId("%%*a")
        expect(HwpFieldCtrlId.revisionClipping.rawValue) == makeCtrlId("%%*C")
        expect(HwpFieldCtrlId.revisionSawtooth.rawValue) == makeCtrlId("%%*S")
        expect(HwpFieldCtrlId.revisionThinking.rawValue) == makeCtrlId("%%*T")
        expect(HwpFieldCtrlId.revisionPraise.rawValue) == makeCtrlId("%%*P")
        expect(HwpFieldCtrlId.revisionLine.rawValue) == makeCtrlId("%%*L")
        expect(HwpFieldCtrlId.revisionSimpleChange.rawValue) == makeCtrlId("%%*c")
        expect(HwpFieldCtrlId.revisionHyperLink.rawValue) == makeCtrlId("%%*h")
        expect(HwpFieldCtrlId.revisionLineAttach.rawValue) == makeCtrlId("%%*A")
        expect(HwpFieldCtrlId.revisionLineLink.rawValue) == makeCtrlId("%%*i")
        expect(HwpFieldCtrlId.revisionLineRansfer.rawValue) == makeCtrlId("%%*t")
        expect(HwpFieldCtrlId.revisionRightMove.rawValue) == makeCtrlId("%%*r")
        expect(HwpFieldCtrlId.revisionLeftMove.rawValue) == makeCtrlId("%%&l")
        expect(HwpFieldCtrlId.revisionTransfer.rawValue) == makeCtrlId("%%*n")
        expect(HwpFieldCtrlId.revisionSimpleInsert.rawValue) == makeCtrlId("%%*e")
        expect(HwpFieldCtrlId.revisionSplit.rawValue) == makeCtrlId("%spl")
        expect(HwpFieldCtrlId.revisionChange.rawValue) == makeCtrlId("%%mr")

        expect(HwpFieldCtrlId.memo.rawValue) == makeCtrlId("%%me")
        expect(HwpFieldCtrlId.privateInfoSecurity.rawValue) == makeCtrlId("%cpr")
        expect(HwpFieldCtrlId.tableOfContents.rawValue) == makeCtrlId("%toc")

        let revisionIds: [HwpFieldCtrlId] = [
            .revisionSign, .revisionDelete, .revisionAttach, .revisionClipping,
            .revisionSawtooth, .revisionThinking, .revisionPraise, .revisionLine,
            .revisionSimpleChange, .revisionHyperLink, .revisionLineAttach,
            .revisionLineLink, .revisionLineRansfer, .revisionRightMove,
            .revisionLeftMove, .revisionTransfer, .revisionSimpleInsert,
            .revisionSplit, .revisionChange,
        ]
        expect(revisionIds.allSatisfy(\.isRevision)) == true
        expect(HwpFieldCtrlId.memo.isRevision) == false
        expect(HwpFieldCtrlId.hyperLink.isRevision) == false
    }

    // swiftlint:disable:next function_body_length
    func testCtrlIdCodableRoundTrip() throws {
        let header = HwpCtrlHeader(
            ctrlId: 0x1234_5678,
            rawPayload: Data([0x78, 0x56, 0x34, 0x12]),
            unknownChildren: []
        )
        func otherControl(_ ctrlId: HwpOtherCtrlId) -> HwpOtherControl {
            HwpOtherControl(
                ctrlId: ctrlId,
                rawTrailing: Data([0xAA]),
                rawPayload: Data([0xAA]),
                ctrlDataRecords: [],
                unknownChildren: []
            )
        }
        func shapeControl(_ ctrlId: HwpCommonCtrlId) -> HwpShapeControl {
            HwpShapeControl(
                ctrlId: ctrlId,
                commonCtrlProperty: nil,
                rawPayload: littleEndianData(ctrlId.rawValue),
                rawTrailing: Data(),
                shapeComponentArray: [],
                eqEditArray: [],
                eqEditRecords: [],
                ctrlDataRecords: [],
                unknownChildren: []
            )
        }
        let values: [HwpCtrlId] = [
            .table(
                HwpTable(
                    commonCtrlProperty: try commonCtrlProperty(.table),
                    tableProperty: tableProperty(),
                    rawPayload: Data([0x6C, 0x62, 0x74, 0x24]),
                    rawTrailing: Data(),
                    cellArray: [],
                    unknownChildren: []
                )
            ),
            .section(HwpSectionDef()),
            .column(HwpColumn()),
            .shape(shapeControl(.picture)),
            .line(shapeControl(.line)),
            .rectangle(shapeControl(.rectangle)),
            .ellipse(shapeControl(.ellipse)),
            .arc(shapeControl(.arc)),
            .polygon(shapeControl(.polygon)),
            .curve(shapeControl(.curve)),
            .equation(shapeControl(.equation)),
            .equationLegacy(shapeControl(.equationLegacy)),
            .picture(shapeControl(.picture)),
            .ole(shapeControl(.ole)),
            .container(shapeControl(.container)),
            .genShapeObject(
                HwpGenShapeObject(
                    commonCtrlProperty: try commonCtrlProperty(.genShapeObject),
                    rawPayload: Data([0x6F, 0x73, 0x67, 0x24]),
                    rawTrailing: Data(),
                    shapeComponentArray: [],
                    ctrlDataRecords: [],
                    unknownChildren: []
                )
            ),
            .pageNumberPosition(
                HwpPageNumberPosition(
                    otherCtrlId: .pageNumberPosition,
                    property: 1,
                    userSymbol: 0,
                    headDecoration: 45,
                    tailDecoration: 45,
                    unused: 45,
                    unknown: 0,
                    rawPayload: Data([0x70, 0x67, 0x6E, 0x70]),
                    rawTrailing: Data(),
                    unknownChildren: []
                )
            ),
            .header(HwpListControl(header: header, listArray: [], unknownChildren: [])),
            .footer(HwpListControl(header: header, listArray: [], unknownChildren: [])),
            .footnote(HwpListControl(header: header, listArray: [], unknownChildren: [])),
            .endnote(HwpListControl(header: header, listArray: [], unknownChildren: [])),
            .form(otherControl(.form)),
            .autoNumber(otherControl(.autoNumber)),
            .newNumber(otherControl(.newNumber)),
            .pageHide(otherControl(.pageHide)),
            .pageCT(otherControl(.pageCT)),
            .indexmark(otherControl(.indexmark)),
            .bookmark(otherControl(.bookmark)),
            .overlapping(otherControl(.overlapping)),
            .comment(otherControl(.comment)),
            .hiddenComment(otherControl(.hiddenComment)),
            .other(otherControl(.pageCT)),
            .hyperLink(
                HwpHyperlink(
                    ctrlId: HwpFieldCtrlId.hyperLink.rawValue,
                    property: 0,
                    unknownPrefix: 0,
                    urlLength: 0,
                    urlLengthRawPayload: Data([0x00, 0x00]),
                    url: "",
                    urlRawPayload: Data(),
                    rawTrailing: Data(),
                    rawPayload: Data([0x6B, 0x6C, 0x68, 0x25]),
                    unknownChildren: []
                )
            ),
            .memo(
                HwpFieldControl(
                    ctrlId: .memo,
                    rawTrailing: Data([0xAA]),
                    fieldParameterHeaderRawPayload: nil,
                    fieldParameter: nil,
                    rawPayload: Data([0x6D, 0x65, 0x25, 0x25, 0xAA]),
                    unknownChildren: []
                )
            ),
            .revision(
                HwpFieldControl(
                    ctrlId: .revisionSign,
                    rawTrailing: Data([0xAA]),
                    fieldParameterHeaderRawPayload: nil,
                    fieldParameter: nil,
                    rawPayload: Data([0x67, 0x6E, 0x72, 0x25, 0xAA]),
                    unknownChildren: []
                )
            ),
            .field(
                HwpFieldControl(
                    ctrlId: .date,
                    rawTrailing: Data([0xAA]),
                    fieldParameterHeaderRawPayload: nil,
                    fieldParameter: nil,
                    rawPayload: Data([0x65, 0x74, 0x64, 0x24, 0xAA]),
                    unknownChildren: []
                )
            ),
            .notImplemented(header),
            .unknown(header),
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: data)
            expect(decoded) == value
        }
    }

    func testCtrlIdDecodeFailsForEmptyObject() {
        expect {
            _ = try JSONDecoder().decode(HwpCtrlId.self, from: Data("{}".utf8))
        }.to(throwError())
    }

    func testCtrlIdDecodeFailsForMultipleCases() {
        let data = Data(
            """
            {
              "notImplemented": {
                "ctrlId": 305419896,
                "rawPayload": [120, 86, 52, 18],
                "unknownChildren": []
              },
              "unknown": {
                "ctrlId": 305419896,
                "rawPayload": [120, 86, 52, 18],
                "unknownChildren": []
              }
            }
            """.utf8
        )

        expect {
            _ = try JSONDecoder().decode(HwpCtrlId.self, from: data)
        }.to(throwError { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return fail("Expected dataCorrupted, got \(error)")
            }
            expect(context.debugDescription) ==
                "Expected exactly one HwpCtrlId case, got 2."
        })
    }
}

private func commonCtrlProperty(_ ctrlId: HwpCommonCtrlId) throws -> HwpCommonCtrlProperty {
    var reader = DataReader(commonCtrlPropertyPayload(ctrlId: ctrlId.rawValue))
    return try HwpCommonCtrlProperty(&reader)
}

private func commonCtrlPropertyPayload(ctrlId: UInt32) -> Data {
    var data = Data()
    data.append(littleEndianData(ctrlId))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(HWPUNIT(0)))
    data.append(littleEndianData(Int32(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(HWPUNIT16(0)))
    data.append(littleEndianData(UInt32(0)))
    data.append(littleEndianData(Int32(0)))
    return data
}

private func tableProperty() -> HwpTableProperty {
    HwpTableProperty(
        property: 0,
        rowCount: 0,
        columnCount: 0,
        cellSpacing: 0,
        leftInnerMargin: 0,
        rightInnerMargin: 0,
        topInnerMargin: 0,
        bottomInnerMargin: 0,
        rowSize: [],
        borderFillId: 0,
        validZoneInfoSize: nil,
        zonePropertyArray: nil,
        rawPayload: Data(),
        rawTrailing: Data()
    )
}

private func semanticCommonControlIds() throws -> [(id: HwpCommonCtrlId, name: String)] {
    let controls: [HwpCtrlId] = [
        .table(
            HwpTable(
                commonCtrlProperty: try commonCtrlProperty(.table),
                tableProperty: tableProperty(),
                rawPayload: littleEndianData(HwpCommonCtrlId.table.rawValue),
                rawTrailing: Data(),
                cellArray: [],
                unknownChildren: []
            )
        ),
        .line(shapeControl(.line)),
        .rectangle(shapeControl(.rectangle)),
        .ellipse(shapeControl(.ellipse)),
        .arc(shapeControl(.arc)),
        .polygon(shapeControl(.polygon)),
        .curve(shapeControl(.curve)),
        .equation(shapeControl(.equation)),
        .equationLegacy(shapeControl(.equationLegacy)),
        .picture(shapeControl(.picture)),
        .ole(shapeControl(.ole)),
        .container(shapeControl(.container)),
        .genShapeObject(
            HwpGenShapeObject(
                commonCtrlProperty: try commonCtrlProperty(.genShapeObject),
                rawPayload: littleEndianData(HwpCommonCtrlId.genShapeObject.rawValue),
                rawTrailing: Data(),
                shapeComponentArray: [],
                ctrlDataRecords: [],
                unknownChildren: []
            )
        ),
    ]

    return controls.compactMap(semanticCommonControlId)
}

// swiftlint:disable:next cyclomatic_complexity
private func semanticCommonControlId(
    _ control: HwpCtrlId
) -> (id: HwpCommonCtrlId, name: String)? {
    switch control {
    case .table:
        (.table, "table")
    case .line:
        (.line, "line")
    case .rectangle:
        (.rectangle, "rectangle")
    case .ellipse:
        (.ellipse, "ellipse")
    case .arc:
        (.arc, "arc")
    case .polygon:
        (.polygon, "polygon")
    case .curve:
        (.curve, "curve")
    case .equation:
        (.equation, "equation")
    case .equationLegacy:
        (.equationLegacy, "equationLegacy")
    case .picture:
        (.picture, "picture")
    case .ole:
        (.ole, "ole")
    case .container:
        (.container, "container")
    case .genShapeObject:
        (.genShapeObject, "genShapeObject")
    default:
        nil
    }
}

private func shapeControl(_ ctrlId: HwpCommonCtrlId) -> HwpShapeControl {
    HwpShapeControl(
        ctrlId: ctrlId,
        commonCtrlProperty: nil,
        rawPayload: littleEndianData(ctrlId.rawValue),
        rawTrailing: Data(),
        shapeComponentArray: [],
        eqEditArray: [],
        eqEditRecords: [],
        ctrlDataRecords: [],
        unknownChildren: []
    )
}

private func semanticOtherControlIds() -> [(id: HwpOtherCtrlId, name: String)] {
    let header = HwpCtrlHeader(
        ctrlId: 0x1234_5678,
        rawPayload: Data([0x78, 0x56, 0x34, 0x12]),
        unknownChildren: []
    )
    let listControl = HwpListControl(header: header, listArray: [], unknownChildren: [])
    let controls: [HwpCtrlId] = [
        .section(HwpSectionDef()),
        .column(HwpColumn()),
        .pageNumberPosition(
            HwpPageNumberPosition(
                otherCtrlId: .pageNumberPosition,
                property: 1,
                userSymbol: 0,
                headDecoration: 45,
                tailDecoration: 45,
                unused: 45,
                unknown: 0,
                rawPayload: Data([0x70, 0x67, 0x6E, 0x70]),
                rawTrailing: Data(),
                unknownChildren: []
            )
        ),
        .header(listControl),
        .footer(listControl),
        .footnote(listControl),
        .endnote(listControl),
        .form(otherControl(.form)),
        .autoNumber(otherControl(.autoNumber)),
        .newNumber(otherControl(.newNumber)),
        .pageHide(otherControl(.pageHide)),
        .pageCT(otherControl(.pageCT)),
        .indexmark(otherControl(.indexmark)),
        .bookmark(otherControl(.bookmark)),
        .overlapping(otherControl(.overlapping)),
        .comment(otherControl(.comment)),
        .hiddenComment(otherControl(.hiddenComment)),
    ]

    return controls.compactMap(semanticOtherControlId)
}

// swiftlint:disable:next cyclomatic_complexity
private func semanticOtherControlId(_ control: HwpCtrlId) -> (id: HwpOtherCtrlId, name: String)? {
    switch control {
    case .section:
        (.section, "section")
    case .column:
        (.column, "column")
    case .pageNumberPosition:
        (.pageNumberPosition, "pageNumberPosition")
    case .header:
        (.header, "header")
    case .footer:
        (.footer, "footer")
    case .footnote:
        (.footnote, "footnote")
    case .endnote:
        (.endnote, "endnote")
    case .form:
        (.form, "form")
    case .autoNumber:
        (.autoNumber, "autoNumber")
    case .newNumber:
        (.newNumber, "newNumber")
    case .pageHide:
        (.pageHide, "pageHide")
    case .pageCT:
        (.pageCT, "pageCT")
    case .indexmark:
        (.indexmark, "indexmark")
    case .bookmark:
        (.bookmark, "bookmark")
    case .overlapping:
        (.overlapping, "overlapping")
    case .comment:
        (.comment, "comment")
    case .hiddenComment:
        (.hiddenComment, "hiddenComment")
    default:
        nil
    }
}

private func otherControl(_ ctrlId: HwpOtherCtrlId) -> HwpOtherControl {
    HwpOtherControl(
        ctrlId: ctrlId,
        rawTrailing: Data([0xAA]),
        rawPayload: concatenatedData(littleEndianData(ctrlId.rawValue), Data([0xAA])),
        ctrlDataRecords: [],
        unknownChildren: []
    )
}

private func littleEndianData(_ value: some FixedWidthInteger) -> Data {
    var littleEndian = value.littleEndian
    return withUnsafeBytes(of: &littleEndian) { Data($0) }
}

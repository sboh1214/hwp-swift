@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ListControlRealFixturePreservationTests: XCTestCase {
    func testHeaderFooterFixtureListControlsSurviveCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "header-footer")

        let header = try listControl("header", in: hwp)
        let footer = try listControl("footer", in: hwp)

        assertHeaderFooterControl(header, ctrlId: .header, text: "CoreHwp header fixture")
        assertHeaderFooterControl(footer, ctrlId: .footer, text: "CoreHwp footer fixture")
        assertListControlRoundTripPreservesRawPayloads(
            original: header,
            roundTripped: try roundTrippedListControl("header", header)
        )
        assertListControlRoundTripPreservesRawPayloads(
            original: footer,
            roundTripped: try roundTrippedListControl("footer", footer)
        )
    }

    func testHeaderFooterFixtureListControlsSurviveHwpFileCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "header-footer")
        let decoded = try hwpFileRoundTrip(hwp)

        let header = try listControl("header", in: hwp)
        let footer = try listControl("footer", in: hwp)
        let decodedHeader = try listControl("header", in: decoded)
        let decodedFooter = try listControl("footer", in: decoded)

        assertHeaderFooterControl(decodedHeader, ctrlId: .header, text: "CoreHwp header fixture")
        assertHeaderFooterControl(decodedFooter, ctrlId: .footer, text: "CoreHwp footer fixture")
        assertListControlRoundTripPreservesRawPayloads(
            original: header,
            roundTripped: decodedHeader
        )
        assertListControlRoundTripPreservesRawPayloads(
            original: footer,
            roundTripped: decodedFooter
        )
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }

    func testFootnoteEndnoteFixtureListControlsSurviveCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "footnote-endnote")

        let footnote = try listControl("footnote", in: hwp)
        let endnote = try listControl("endnote", in: hwp)

        assertFootnoteEndnoteControl(footnote, ctrlId: .footnote, text: "CoreHwp footnote fixture")
        assertFootnoteEndnoteControl(endnote, ctrlId: .endnote, text: "CoreHwp endnote fixture")
        assertListControlRoundTripPreservesRawPayloads(
            original: footnote,
            roundTripped: try roundTrippedListControl("footnote", footnote)
        )
        assertListControlRoundTripPreservesRawPayloads(
            original: endnote,
            roundTripped: try roundTrippedListControl("endnote", endnote)
        )
    }

    func testFootnoteEndnoteFixtureListControlsSurviveHwpFileCodableRoundTrip() throws {
        let hwp = try openHwp(#file, "footnote-endnote")
        let decoded = try hwpFileRoundTrip(hwp)

        let footnote = try listControl("footnote", in: hwp)
        let endnote = try listControl("endnote", in: hwp)
        let decodedFootnote = try listControl("footnote", in: decoded)
        let decodedEndnote = try listControl("endnote", in: decoded)

        assertFootnoteEndnoteControl(
            decodedFootnote,
            ctrlId: .footnote,
            text: "CoreHwp footnote fixture"
        )
        assertFootnoteEndnoteControl(
            decodedEndnote,
            ctrlId: .endnote,
            text: "CoreHwp endnote fixture"
        )
        assertListControlRoundTripPreservesRawPayloads(
            original: footnote,
            roundTripped: decodedFootnote
        )
        assertListControlRoundTripPreservesRawPayloads(
            original: endnote,
            roundTripped: decodedEndnote
        )
        expect(decoded.docInfo.rawPayload) == hwp.docInfo.rawPayload
        expect(decoded.sectionArray.map(\.rawPayload)) == hwp.sectionArray.map(\.rawPayload)
    }
}

private func listControl(_ kind: String, in hwp: HwpFile) throws -> HwpListControl {
    guard let control = FixtureDerivedValues
        .listControls(from: hwp)
        .first(where: { $0.kind == kind })?
        .control
    else {
        fail("Expected fixture to contain \(kind) list control")
        throw HwpError.recordDoesNotExist(tag: HwpSectionTag.ctrlHeader.rawValue)
    }

    return control
}

private func roundTrippedListControl(
    _ kind: String,
    _ control: HwpListControl
) throws -> HwpListControl {
    let encoded: Data
    switch kind {
    case "header":
        encoded = try JSONEncoder().encode(HwpCtrlId.header(control))
    case "footer":
        encoded = try JSONEncoder().encode(HwpCtrlId.footer(control))
    case "footnote":
        encoded = try JSONEncoder().encode(HwpCtrlId.footnote(control))
    case "endnote":
        encoded = try JSONEncoder().encode(HwpCtrlId.endnote(control))
    default:
        fail("Unsupported list control kind \(kind)")
        throw HwpError.invalidCtrlId(ctrlId: control.header.ctrlId)
    }

    let decoded = try JSONDecoder().decode(HwpCtrlId.self, from: encoded)
    switch (kind, decoded) {
    case let ("header", .header(roundTripped)),
         let ("footer", .footer(roundTripped)),
         let ("footnote", .footnote(roundTripped)),
         let ("endnote", .endnote(roundTripped)):
        return roundTripped
    default:
        fail("Expected \(kind) after Codable round-trip")
        throw HwpError.invalidCtrlId(ctrlId: control.header.ctrlId)
    }
}

private func hwpFileRoundTrip(_ hwp: HwpFile) throws -> HwpFile {
    try JSONDecoder().decode(HwpFile.self, from: JSONEncoder().encode(hwp))
}

private func assertHeaderFooterControl(
    _ control: HwpListControl,
    ctrlId: HwpOtherCtrlId,
    text: String
) {
    assertListControl(
        control,
        expected: ListControlExpectation(
            ctrlId: ctrlId,
            text: text,
            headerPayloadLength: 12,
            listHeaderPayloadLength: 34,
            listHeaderTrailingLength: 26
        )
    )
}

private func assertFootnoteEndnoteControl(
    _ control: HwpListControl,
    ctrlId: HwpOtherCtrlId,
    text: String
) {
    assertListControl(
        control,
        expected: ListControlExpectation(
            ctrlId: ctrlId,
            text: text,
            headerPayloadLength: 20,
            listHeaderPayloadLength: 16,
            listHeaderTrailingLength: 8
        )
    )
}

private func assertListControl(
    _ control: HwpListControl,
    expected: ListControlExpectation
) {
    expect(control.header.ctrlId) == expected.ctrlId.rawValue
    expect(control.header.rawPayload.count) == expected.headerPayloadLength
    expect(control.header.unknownChildren).notTo(beEmpty())
    expect(control.listArray.count) == 1
    expect(control.unknownChildren).to(beEmpty())

    guard let list = control.listArray.first else {
        return
    }

    expect(list.header.paragraphCount) == 1
    expect(list.header.rawPayload) == list.headerRawPayload
    expect(list.header.rawPayload.count) == expected.listHeaderPayloadLength
    expect(list.header.rawTrailing.count) == expected.listHeaderTrailingLength
    expect(list.header.rawTrailingWords?.count) == expected.listHeaderTrailingLength / 2
    expect(list.headerUnknownChildren).to(beEmpty())
    expect(list.paragraphArray.count) == 1
    expect(visibleText(from: list.paragraphArray)).to(contain(expected.text))
}

private struct ListControlExpectation {
    let ctrlId: HwpOtherCtrlId
    let text: String
    let headerPayloadLength: Int
    let listHeaderPayloadLength: Int
    let listHeaderTrailingLength: Int
}

private func assertListControlRoundTripPreservesRawPayloads(
    original: HwpListControl,
    roundTripped: HwpListControl
) {
    expect(roundTripped.header.ctrlId) == original.header.ctrlId
    expect(roundTripped.header.rawPayload) == original.header.rawPayload
    expect(roundTripped.header.unknownChildren) == original.header.unknownChildren
    expect(roundTripped.unknownChildren) == original.unknownChildren
    expect(roundTripped.listArray.count) == original.listArray.count

    for (originalList, roundTrippedList) in zip(original.listArray, roundTripped.listArray) {
        expect(roundTrippedList.header.rawPayload) == originalList.header.rawPayload
        expect(roundTrippedList.headerRawPayload) == originalList.headerRawPayload
        expect(roundTrippedList.header.rawTrailing) == originalList.header.rawTrailing
        expect(roundTrippedList.header.rawTrailingWords) == originalList.header.rawTrailingWords
        expect(roundTrippedList.headerUnknownChildren) == originalList.headerUnknownChildren
        assertParagraphRoundTripPreservesRawPayloads(
            original: originalList.paragraphArray,
            roundTripped: roundTrippedList.paragraphArray
        )
    }
}

private func assertParagraphRoundTripPreservesRawPayloads(
    original: [HwpParagraph],
    roundTripped: [HwpParagraph]
) {
    expect(roundTripped.count) == original.count
    expect(visibleText(from: roundTripped)) == visibleText(from: original)
    expect(roundTripped.map(\.paraHeader.rawPayload)) == original.map(\.paraHeader.rawPayload)
    expect(roundTripped.map { $0.paraText?.rawPayload }) ==
        original.map { $0.paraText?.rawPayload }
    expect(roundTripped.map(\.paraCharShape.rawPayload)) == original.map(\.paraCharShape.rawPayload)
    expect(roundTripped.map(\.paraLineSeg.rawPayload)) == original.map(\.paraLineSeg.rawPayload)
    expect(roundTripped.map { $0.paraRangeTagArray?.map(\.rawPayload) }) == original.map {
        $0.paraRangeTagArray?.map(\.rawPayload)
    }
    expect(roundTripped.map { $0.listHeaderArray?.map(\.rawPayload) }) == original.map {
        $0.listHeaderArray?.map(\.rawPayload)
    }
    expect(roundTripped.map(\.ctrlHeaderArray)) == original.map(\.ctrlHeaderArray)
    expect(roundTripped.map(\.unknownChildren)) == original.map(\.unknownChildren)
    expect(roundTripped.map { $0.ctrlHeaderArray?.map(FixtureDerivedValues.controlName) }) ==
        original.map { $0.ctrlHeaderArray?.map(FixtureDerivedValues.controlName) }
}

private func visibleText(from paragraphs: [HwpParagraph]) -> String {
    paragraphs
        .compactMap(\.paraText)
        .flatMap(\.charArray)
        .compactMap { char -> UnicodeScalar? in
            guard char.type == .char else {
                return nil
            }
            return UnicodeScalar(Int(char.value))
        }
        .map(String.init)
        .joined()
}

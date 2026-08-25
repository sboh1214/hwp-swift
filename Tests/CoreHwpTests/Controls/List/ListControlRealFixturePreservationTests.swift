@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class ListControlRealFixturePreservationTests: XCTestCase {
    func testHeaderFooterFixtureListControlsParseExpectedContent() throws {
        let hwp = try openHwp(#file, "header-footer")

        let header = try listControl("header", in: hwp)
        let footer = try listControl("footer", in: hwp)

        assertHeaderFooterControl(header, ctrlId: .header, text: "CoreHwp header fixture")
        assertHeaderFooterControl(footer, ctrlId: .footer, text: "CoreHwp footer fixture")
    }

    func testFootnoteEndnoteFixtureListControlsParseExpectedContent() throws {
        let hwp = try openHwp(#file, "footnote-endnote")

        let footnote = try listControl("footnote", in: hwp)
        let endnote = try listControl("endnote", in: hwp)

        assertFootnoteEndnoteControl(footnote, ctrlId: .footnote, text: "CoreHwp footnote fixture")
        assertFootnoteEndnoteControl(endnote, ctrlId: .endnote, text: "CoreHwp endnote fixture")
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

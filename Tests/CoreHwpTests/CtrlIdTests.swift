@testable import CoreHwp
import Nimble
import XCTest

private func makeCtrlId(_ string: String) -> UInt32 {
    precondition(string.count == 4)
    let array = string.asciiValues.map { UInt32($0) }
    return array[0] << 24 + array[1] << 16 + array[2] << 8 + array[3]
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

        expect(HwpCommonCtrlId.equation.rawValue) == makeCtrlId("equd")
        expect(HwpCommonCtrlId.picture.rawValue) == makeCtrlId("$pic")
        expect(HwpCommonCtrlId.ole.rawValue) == makeCtrlId("$ole")
        expect(HwpCommonCtrlId.container.rawValue) == makeCtrlId("$con")

        expect(HwpCommonCtrlId.genShapeObject.rawValue) == makeCtrlId("gso ")
    }

    func testOtherCtrlID() {
        expect(HwpOtherCtrlId.section.rawValue) == makeCtrlId("secd")
        expect(HwpOtherCtrlId.column.rawValue) == makeCtrlId("cold")
        expect(HwpOtherCtrlId.header.rawValue) == makeCtrlId("head")
        expect(HwpOtherCtrlId.footer.rawValue) == makeCtrlId("foot")
        expect(HwpOtherCtrlId.footnote.rawValue) == makeCtrlId("fn  ")
        expect(HwpOtherCtrlId.endnote.rawValue) == makeCtrlId("en  ")
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
    }
}

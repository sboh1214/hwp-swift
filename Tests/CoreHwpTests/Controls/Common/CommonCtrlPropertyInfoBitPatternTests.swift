@testable import CoreHwp
import Nimble
import XCTest

final class CommonCtrlPropertyInfoBitPatternTests: XCTestCase {
    func testLoadDecodesRelativeToAlignmentAndTextWrapBits() throws {
        let rawValue: UInt32 = 0b1 // treat as char
            | (2 << 3) // vertical relative to: paragraph
            | (1 << 5) // vertical alignment: center
            | (3 << 8) // horizontal relative to: paragraph
            | (2 << 10) // horizontal alignment: bottom or right
            | (5 << 21) // text wrap: in front of text

        let info = try HwpCommonCtrlPropertyInfo.load(rawValue)

        expect(info.rawValue) == rawValue
        expect(info.treatAsChar) == true
        expect(info.verticalRelativeToRawValue) == 2
        expect(info.verticalRelativeTo) == .paragraph
        expect(info.verticalAlignment) == .center
        expect(info.horizontalRelativeToRawValue) == 3
        expect(info.horizontalRelativeTo) == .paragraph
        expect(info.horizontalAlignment) == .bottomOrRight
        expect(info.textWrapRawValue) == 5
        expect(info.textWrap) == .inFrontOfText
    }

    func testVerticalRelativeToCoversPaperPageAndParagraph() throws {
        expect(try HwpCommonCtrlPropertyInfo.load(0 << 3).verticalRelativeTo) == .paper
        expect(try HwpCommonCtrlPropertyInfo.load(1 << 3).verticalRelativeTo) == .page
        expect(try HwpCommonCtrlPropertyInfo.load(2 << 3).verticalRelativeTo) == .paragraph
        // raw 3은 표 70에 정의되지 않았다.
        expect(try HwpCommonCtrlPropertyInfo.load(3 << 3).verticalRelativeTo).to(beNil())
        expect(try HwpCommonCtrlPropertyInfo.load(3 << 3).verticalRelativeToRawValue) == 3
    }

    func testHorizontalRelativeToCoversPaperPageColumnAndParagraph() throws {
        expect(try HwpCommonCtrlPropertyInfo.load(0 << 8).horizontalRelativeTo) == .paper
        expect(try HwpCommonCtrlPropertyInfo.load(1 << 8).horizontalRelativeTo) == .page
        expect(try HwpCommonCtrlPropertyInfo.load(2 << 8).horizontalRelativeTo) == .column
        expect(try HwpCommonCtrlPropertyInfo.load(3 << 8).horizontalRelativeTo) == .paragraph
    }

    func testRelativeAlignmentCoversInsideAndOutside() throws {
        expect(try HwpCommonCtrlPropertyInfo.load(3 << 5).verticalAlignment) == .inside
        expect(try HwpCommonCtrlPropertyInfo.load(4 << 5).verticalAlignment) == .outside
        expect(try HwpCommonCtrlPropertyInfo.load(4 << 10).horizontalAlignment) == .outside
        // raw 5-7은 정의되지 않았다.
        expect(try HwpCommonCtrlPropertyInfo.load(5 << 5).verticalAlignment).to(beNil())
        expect(try HwpCommonCtrlPropertyInfo.load(7 << 10).horizontalAlignment).to(beNil())
    }

    func testTextWrapMatchesSpecCorrectedOrder() throws {
        let expectedCases: [HwpCommonCtrlTextWrap?] = [
            .square, .tight, .through, .topAndBottom, .behindText, .inFrontOfText, nil, nil,
        ]

        for (rawValue, expectedCase) in expectedCases.enumerated() {
            let info = try HwpCommonCtrlPropertyInfo.load(UInt32(rawValue) << 21)
            expect(info.textWrapRawValue) == rawValue
            if let expectedCase {
                expect(info.textWrap) == expectedCase
            } else {
                expect(info.textWrap).to(beNil())
            }
        }
    }
}

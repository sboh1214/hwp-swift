@testable import CoreHwp
import Nimble
import XCTest

final class CommonCtrlPropertyInfoBitPatternTests: XCTestCase {
    func testLoadDecodesRelativeToAlignmentAndTextWrapBits() throws {
        // 리터럴 OR 체인 한 식은 느린 머신(CI)에서 타입체크 시간 초과 —
        // 문장 단위로 나눠 각각 독립 타입체크되게 한다
        var rawValue: UInt32 = 0b1 // treat as char
        rawValue |= 2 << 3 // vertical relative to: paragraph
        rawValue |= 1 << 5 // vertical alignment: center
        rawValue |= 3 << 8 // horizontal relative to: paragraph
        rawValue |= 2 << 10 // horizontal alignment: bottom or right
        rawValue |= 3 << 21 // text wrap: in front of text

        let info = try HwpCommonCtrlPropertyInfo.load(rawValue)

        expect(info.rawValue) == rawValue
        expect(info.treatAsChar) == true
        expect(info.verticalRelativeToRawValue) == 2
        expect(info.verticalRelativeTo) == .paragraph
        expect(info.verticalAlignment) == .center
        expect(info.horizontalRelativeToRawValue) == 3
        expect(info.horizontalRelativeTo) == .paragraph
        expect(info.horizontalAlignment) == .bottomOrRight
        expect(info.textWrapRawValue) == 3
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

    func testTextWrapMatchesMeasuredHwp5Order() throws {
        // ErrataAudit 26b: 바이너리 HWP5 실측 매핑 (공개 스펙 6값과 다름).
        let expectedCases: [HwpCommonCtrlTextWrap?] = [
            .square, .topAndBottom, .behindText, .inFrontOfText, nil, nil, nil, nil,
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

@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class DataExtensionPrimitiveTests: XCTestCase {
    func testLittleEndianUInt16ArrayIfAligned() {
        expect(Data([0x34, 0x12, 0xCD, 0xAB]).littleEndianUInt16ArrayIfAligned()) ==
            [0x1234, 0xABCD]
        expect(Data().littleEndianUInt16ArrayIfAligned()) == []
        expect(Data([0x34]).littleEndianUInt16ArrayIfAligned()).to(beNil())
    }

    func testLittleEndianUInt32ArrayWithTrailing() {
        let payload = Data([
            0x04, 0x03, 0x02, 0x01,
            0xDD, 0xCC, 0xBB, 0xAA,
            0xEE,
        ])
        let parsed = payload.littleEndianUInt32ArrayWithTrailing(minimumValueCount: 1)

        expect(parsed?.values) == [0x0102_0304, 0xAABB_CCDD]
        expect(parsed?.rawTrailing) == Data([0xEE])
        expect(Data([0x34, 0x12, 0x00]).littleEndianUInt32ArrayWithTrailing(
            minimumValueCount: 1
        )).to(beNil())
        expect(Data([0x34]).littleEndianUInt32ArrayWithTrailing()?.values).to(beEmpty())
        expect(Data([0x34]).littleEndianUInt32ArrayWithTrailing()?.rawTrailing) ==
            Data([0x34])
        expect(Data().littleEndianUInt32ArrayWithTrailing()?.rawTrailing).to(beEmpty())
        expect(Data().littleEndianUInt32ArrayWithTrailing(
            minimumValueCount: -1
        )).to(beNil())
    }
}

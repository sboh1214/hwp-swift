@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 손상 CFB의 거대 섹터 ID가 크래시(32비트 Int 변환/오프셋 곱 트랩) 없이
/// nil로 거부되는지 — malformed 입력은 typed error/nil 규약 (P1).
final class HwpEmbeddedChartMalformedTests: XCTestCase {
    /// v3 CFB 헤더 + FAT 섹터 1개짜리 최소 컨테이너.
    private func minimalCFB(firstDirectorySector: UInt32, fatEntry: UInt32) -> Data {
        var cfb = Data(count: 1024)
        cfb.replaceSubrange(0 ..< 8, with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        func put(_ value: UInt32, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) {
                cfb.replaceSubrange(offset ..< offset + 4, with: $0)
            }
        }
        func put16(_ value: UInt16, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) {
                cfb.replaceSubrange(offset ..< offset + 2, with: $0)
            }
        }
        put16(9, at: 30)
        put16(6, at: 32)
        put(1, at: 44)
        put(firstDirectorySector, at: 48)
        put(4096, at: 56)
        put(0xFFFF_FFFE, at: 60)
        put(0, at: 64)
        put(0, at: 76)
        put(fatEntry, at: 512)
        return cfb
    }

    private func olePayload(_ cfb: Data) -> Data {
        Data([0, 0, 0, 0]) + cfb
    }

    func testHugeDirectorySectorReturnsNilWithoutTrapping() {
        let cfb = minimalCFB(firstDirectorySector: 0x8000_0000, fatEntry: 0xFFFF_FFFE)
        expect(HwpEmbeddedChart.chartXML(fromOLEPayload: self.olePayload(cfb))).to(beNil())
    }

    func testHugeFatChainSectorReturnsNilWithoutTrapping() {
        let cfb = minimalCFB(firstDirectorySector: 0, fatEntry: 0x9000_0000)
        expect(HwpEmbeddedChart.chartXML(fromOLEPayload: self.olePayload(cfb))).to(beNil())
    }

    func testDecodeXMLStringHonorsBOM() {
        // XML 스펙상 UTF-16 스트림은 BOM 필수 — BOM별 디코드가 같은 문자열을
        // 돌려주고, BOM 없는 기본은 UTF-8이다 (P2).
        let xml = "<c:chartSpace/>"
        var utf16LE = Data([0xFF, 0xFE])
        utf16LE.append(xml.data(using: .utf16LittleEndian) ?? Data())
        expect(HwpEmbeddedChart.decodeXMLString(utf16LE)) == xml

        var utf16BE = Data([0xFE, 0xFF])
        utf16BE.append(xml.data(using: .utf16BigEndian) ?? Data())
        expect(HwpEmbeddedChart.decodeXMLString(utf16BE)) == xml

        var utf8BOM = Data([0xEF, 0xBB, 0xBF])
        utf8BOM.append(xml.data(using: .utf8) ?? Data())
        expect(HwpEmbeddedChart.decodeXMLString(utf8BOM)) == xml

        expect(HwpEmbeddedChart.decodeXMLString(xml.data(using: .utf8) ?? Data())) == xml
    }

    func testNearMaxSectorOffsetArithmeticReturnsNil() {
        // Int(exactly:)는 성공하지만 (n+1)*sectorSize 오프셋이 컨테이너를 한참
        // 넘는 ID — 오버플로 검사 경로가 nil을 돌려준다.
        let cfb = minimalCFB(firstDirectorySector: 0x7FFF_FFFE, fatEntry: 0xFFFF_FFFE)
        expect(HwpEmbeddedChart.chartXML(fromOLEPayload: self.olePayload(cfb))).to(beNil())
    }
}

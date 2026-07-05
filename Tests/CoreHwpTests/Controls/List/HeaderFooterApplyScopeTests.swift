@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HeaderFooterApplyScopeTests: XCTestCase {
    func testHeaderFooterFixtureScopeIsBothPages() throws {
        let hwp = try openHwp(#file, "header-footer")
        let controls = hwp.sectionArray
            .flatMap(\.paragraph)
            .flatMap { $0.ctrlHeaderArray ?? [] }

        let header = controls.compactMap(listControlFromHeader).first
        let footer = controls.compactMap(listControlFromFooter).first

        expect(header).toNot(beNil())
        expect(footer).toNot(beNil())
        expect(header?.headerFooterPropertyRawValue) == 0
        expect(header?.headerFooterApplyScope) == HwpHeaderFooterApplyScope.bothPages
        expect(footer?.headerFooterPropertyRawValue) == 0
        expect(footer?.headerFooterApplyScope) == HwpHeaderFooterApplyScope.bothPages
    }

    func testSyntheticPropertyDecodesEvenAndOddScopes() {
        expect(self.listControl(property: 0).headerFooterApplyScope)
            == HwpHeaderFooterApplyScope.bothPages
        expect(self.listControl(property: 1).headerFooterApplyScope)
            == HwpHeaderFooterApplyScope.evenPagesOnly
        expect(self.listControl(property: 2).headerFooterApplyScope)
            == HwpHeaderFooterApplyScope.oddPagesOnly
        // bit 0-1 밖의 bit는 적용 범위에 영향을 주지 않는다.
        expect(self.listControl(property: 0b100).headerFooterApplyScope)
            == HwpHeaderFooterApplyScope.bothPages
    }

    func testShortPayloadFallsBackToBothPages() {
        let control = HwpListControl(
            header: HwpCtrlHeader(
                ctrlId: HwpOtherCtrlId.header.rawValue,
                rawPayload: Data([0x64, 0x61, 0x65, 0x68])
            ),
            listArray: [],
            unknownChildren: []
        )
        expect(control.headerFooterPropertyRawValue).to(beNil())
        expect(control.headerFooterApplyScope) == HwpHeaderFooterApplyScope.bothPages
    }

    func testEndnotePlacementBitsDecodeFromFixtureAndSynthetic() throws {
        // footnote-endnote 픽스처: 미주 모양 속성 0 → 문서의 마지막
        let hwp = try openHwp(#file, "footnote-endnote")
        let sectionDef = hwp.sectionArray
            .flatMap(\.paragraph)
            .compactMap { paragraph -> HwpSectionDef? in
                paragraph.ctrlHeaderArray?.compactMap { ctrl -> HwpSectionDef? in
                    if case let .section(def) = ctrl { return def }
                    return nil
                }.first
            }
            .first
        expect(sectionDef?.endNoteShape.endnotePlacementRawValue) == 0
        expect(sectionDef?.endNoteShape.placesEndnoteAtSectionEnd) == false

        // 표 134 bits 8-9 == 1 → 구역의 마지막
        var shape = HwpFootnoteShape(
            dividerLength: 0, dividerMarginTop: 0, dividerType: 0, dividerThickness: 0
        )
        shape.property = 1 << 8
        expect(shape.endnotePlacementRawValue) == 1
        expect(shape.placesEndnoteAtSectionEnd) == true
    }

    private func listControl(property: UInt32) -> HwpListControl {
        var payload = Data()
        withUnsafeBytes(of: HwpOtherCtrlId.header.rawValue.littleEndian) {
            payload.append(contentsOf: $0)
        }
        withUnsafeBytes(of: property.littleEndian) {
            payload.append(contentsOf: $0)
        }
        return HwpListControl(
            header: HwpCtrlHeader(
                ctrlId: HwpOtherCtrlId.header.rawValue,
                rawPayload: payload
            ),
            listArray: [],
            unknownChildren: []
        )
    }
}

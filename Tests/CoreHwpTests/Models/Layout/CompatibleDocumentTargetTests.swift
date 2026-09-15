@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// 호환 문서 대상 프로그램(표 55) 열거 — 값·OWPML 이름은 한컴 공개 모델
/// `COMPATIBLEDOCTYPE`(`g_CompatiblieDocList`)이 정본이다 (#187).
final class CompatibleDocumentTargetTests: XCTestCase {
    func testRawValuesFollowTheHancomModel() {
        expect(HwpCompatibleDocumentTarget.hwp201X.rawValue) == 0
        expect(HwpCompatibleDocumentTarget.hwp200X.rawValue) == 1
        expect(HwpCompatibleDocumentTarget.msWord.rawValue) == 2
        expect(HwpCompatibleDocumentTarget.hunmin.rawValue) == 4
        // 3은 어느 모델에도 없다 — 소비자는 한글 문서로 다룬다.
        expect(HwpCompatibleDocumentTarget(rawValue: 3)).to(beNil())
    }

    func testOwpmlNamesRoundTrip() {
        for target in HwpCompatibleDocumentTarget.allCases {
            expect(HwpCompatibleDocumentTarget(owpmlName: target.owpmlName)) == target
        }
        expect(HwpCompatibleDocumentTarget.msWord.owpmlName) == "MS_WORD"
        expect(HwpCompatibleDocumentTarget.hwp201X.owpmlName) == "HWP201X"
        expect(HwpCompatibleDocumentTarget.hwp200X.owpmlName) == "HWP200X"
        expect(HwpCompatibleDocumentTarget.hunmin.owpmlName) == "Hunmin"
        // 대소문자는 한컴 모델 그대로다.
        expect(HwpCompatibleDocumentTarget(owpmlName: "ms_word")).to(beNil())
        expect(HwpCompatibleDocumentTarget(owpmlName: "")).to(beNil())
    }

    func testCompatibleDocumentExposesTypedTarget() throws {
        let known = try HwpCompatibleDocument.load(Self.record(target: 2))
        expect(known.target) == .msWord
        let unknown = try HwpCompatibleDocument.load(Self.record(target: 9))
        expect(unknown.targetDocument) == 9
        expect(unknown.target).to(beNil())
    }

    /// 표 54 record — 대상 프로그램 UINT32 하나.
    private static func record(target: UInt32) -> HwpRecord {
        var payload = Data()
        for shift in stride(from: 0, to: 32, by: 8) {
            payload.append(UInt8((target >> UInt32(shift)) & 0xFF))
        }
        return HwpRecord(
            tagId: HwpDocInfoTag.compatibleDocument.rawValue, level: 0, payload: payload
        )
    }

    func testHwpxInitCarriesTargetWithoutBinaryPayload() {
        let diagnostic = HwpUnknownRecord(
            tagId: hwpxSyntheticTagId, level: 0, payload: Data("layoutCompatibility".utf8)
        )
        let document = HwpCompatibleDocument(hwpxTarget: .msWord, unknownChildren: [diagnostic])
        expect(document.targetDocument) == 2
        expect(document.target) == .msWord
        expect(document.rawPayload).to(beEmpty())
        expect(document.targetDocumentRawPayload).to(beEmpty())
        expect(document.layoutCompatibility).to(beNil())
        expect(document.trackChangeArray).to(beEmpty())
        expect(document.unknownChildren) == [diagnostic]
    }

    /// 코퍼스의 실물: `track-changes`만 MS 워드 호환 문서이고 나머지는 한글 문서다.
    func testTrackChangesFixtureIsTheMsWordDocument() throws {
        let trackChanges = try FixtureLoader.load(id: "track-changes")
        let file = try HwpFile(fromPath: trackChanges.documentURL.path)
        expect(file.docInfo.compatibleDocument?.target) == .msWord

        let noori = try FixtureLoader.load(id: "noori")
        let native = try HwpFile(fromPath: noori.documentURL.path)
        expect(native.docInfo.compatibleDocument?.target) == .hwp201X
    }
}

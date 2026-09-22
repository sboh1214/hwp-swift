@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `compatibleDocumentTarget` 축의 직접 핀 (#187) — `HwpxHwpEquivalenceTests`의 다른 축
/// 핀과 같은 규약이지만, 그 파일이 SwiftLint `file_length` 상한에 가까워 여기로 뗐다.
final class HwpxHwpEquivalenceCompatTargetTests: XCTestCase {
    /// 대상 프로그램 축이 **기본값이 아닌 값으로** 성립하는지 핀한다. 등식만 두면 매핑이
    /// 빠져도 코퍼스의 나머지 쌍(전부 `HWP201X` = 0)은 통과하므로, 한글 12.30.0이
    /// MS 워드 호환 문서로 저장한 이 쌍에서 HWPX 쪽 값을 HWP 저장본의 2(`CT_MSWORD`)로
    /// 못박는다. 강등 상태(매핑 전)에는 HWPX 쪽이 nil이었다.
    func testCompatDecorationsPairProjectsTheMsWordTargetOnBothFormats() throws {
        let hwp = try HwpFile(
            fromPath: FixtureLoader.load(id: "compat-decorations").documentURL.path
        )
        let hwpx = try HwpFile(
            fromPath: HwpxFixtureLoader.load(id: "compat-decorations").documentURL.path
        )
        let hwpProjection = DocumentEquivalenceProjection(of: hwp)
        let hwpxProjection = DocumentEquivalenceProjection(of: hwpx)

        expect(hwpProjection.compatibleDocumentTarget) == 2
        expect(hwpxProjection.compatibleDocumentTarget) == 2
        expect(hwpx.docInfo.compatibleDocument?.target) == .msWord
        hwpProjection.assertEqual(to: hwpxProjection, fixtureId: "compat-decorations")
    }

    /// 한글 2007 호환 문서 축의 직접 핀 (#210) — 위 MS 워드 핀과 같은 규약이다. 한글
    /// 12.30.0이 `HWP200X`로 저장한 이 쌍에서 HWPX 쪽 값을 HWP 저장본의 1(`CT_HWP200X`)로
    /// 못박아, 대상 프로그램이 MS 워드 하나만 옮겨지고 나머지가 한글 문서(0)로 접히는
    /// 회귀를 잡는다.
    func testHwp2007DecorationsPairProjectsTheHwp200XTargetOnBothFormats() throws {
        let hwp = try HwpFile(
            fromPath: FixtureLoader.load(id: "hwp2007-decorations").documentURL.path
        )
        let hwpx = try HwpFile(
            fromPath: HwpxFixtureLoader.load(id: "hwp2007-decorations").documentURL.path
        )
        let hwpProjection = DocumentEquivalenceProjection(of: hwp)
        let hwpxProjection = DocumentEquivalenceProjection(of: hwpx)

        expect(hwpProjection.compatibleDocumentTarget) == 1
        expect(hwpxProjection.compatibleDocumentTarget) == 1
        expect(hwp.docInfo.compatibleDocument?.target) == .hwp200X
        expect(hwpx.docInfo.compatibleDocument?.target) == .hwp200X
        hwpProjection.assertEqual(to: hwpxProjection, fixtureId: "hwp2007-decorations")
    }

    /// 한글 문서 쌍은 0으로 같다 — 재저장본에 record가 있고(`HWP201X`) 매퍼가 그것을
    /// 옮긴다. nil ↔ 0으로 갈리는 회귀를 잡는다.
    func testNativePairProjectsZeroOnBothFormats() throws {
        let hwp = try HwpFile(fromPath: FixtureLoader.load(id: "CharShape").documentURL.path)
        let hwpx = try HwpFile(
            fromPath: HwpxFixtureLoader.load(id: "CharShape").documentURL.path
        )
        expect(DocumentEquivalenceProjection(of: hwp).compatibleDocumentTarget) == 0
        expect(DocumentEquivalenceProjection(of: hwpx).compatibleDocumentTarget) == 0
    }
}

@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `sectionSettings` 축의 직접 핀 (#173) — `HwpxHwpEquivalenceTests`의 다른 축 핀과
/// 같은 규약이지만, 그 파일이 SwiftLint `file_length` 상한에 가까워 여기로 뗐다.
final class HwpxHwpEquivalenceSectionSettingsTests: XCTestCase {
    /// 구역 시작 설정 축이 **기본값이 아닌 값으로** 성립하는지 직접 핀한다 (#173).
    /// 등식만 두면 매핑이 뒤집혀도 다른 16쌍(전부 `BOTH`·0)은 통과하므로, 한글
    /// 12.30.0이 `쪽 > 구역 설정... > 종류`를 이어서·홀수·짝수·사용자(5)로 저장한
    /// 4구역 쌍에서 HWPX 쪽 값을 HWP 저장본의 비트(홀수 `0x200000` = 2, 짝수
    /// `0x100000` = 1)로 못박는다. 매핑이 `ODD → 1`이던 종전에는 둘째·셋째
    /// 구역이 서로 바뀌어 읽혔다.
    func testSectionPageStartsOnPairProjectsSameStartSettingsOnBothFormats() throws {
        let hwp = try HwpFile(
            fromPath: FixtureLoader.load(id: "section-page-starts-on").documentURL.path
        )
        let hwpx = try HwpFile(
            fromPath: HwpxFixtureLoader.load(id: "section-page-starts-on").documentURL.path
        )
        let hwpProjection = DocumentEquivalenceProjection(of: hwp)
        let hwpxProjection = DocumentEquivalenceProjection(of: hwpx)

        expect(hwpxProjection.sectionSettings.count) == 4
        expect(hwpxProjection.sectionSettings.map(\.pageStartsOn)) == [0, 2, 1, 0]
        expect(hwpxProjection.sectionSettings.map(\.pageStartNumber)) == [0, 0, 0, 5]
        // 그림·표·수식 시작 번호와 첫 쪽 감추기는 손대지 않았다 — 전부 기본값.
        expect(hwpxProjection.sectionSettings.map(\.pictureStartNumber)) == [0, 0, 0, 0]
        expect(hwpxProjection.sectionSettings.map(\.tableStartNumber)) == [0, 0, 0, 0]
        expect(hwpxProjection.sectionSettings.map(\.equationNumber)) == [0, 0, 0, 0]
        expect(hwpxProjection.sectionSettings.contains {
            $0.hidesFirstHeader || $0.hidesFirstFooter
                || $0.hidesFirstMasterPage || $0.hidesFirstPageNumber
        }) == false
        expect(hwpxProjection.sectionSettings) == hwpProjection.sectionSettings
    }
}

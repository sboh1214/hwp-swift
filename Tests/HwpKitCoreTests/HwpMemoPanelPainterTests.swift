import CoreGraphics
@testable import HwpKitCore
import Nimble
import XCTest

final class HwpMemoPanelPainterTests: XCTestCase {
    func testPanelCapsBalloonCountPerPage() {
        let balloon = HwpMemoPanelPainter.Balloon(
            anchorY: 0, author: "author", dateText: "2026/07/16 00:00", body: "memo body"
        )
        let pageSize = CGSize(width: 595, height: 842)
        let cap = HwpMemoPanelPainter.maxBalloonsPerPage

        let atCap = HwpMemoPanelPainter.panel(
            balloons: Array(repeating: balloon, count: cap), pageSize: pageSize
        )
        let overCap = HwpMemoPanelPainter.panel(
            balloons: Array(repeating: balloon, count: cap + 50), pageSize: pageSize
        )
        let underCap = HwpMemoPanelPainter.panel(
            balloons: Array(repeating: balloon, count: cap - 1), pageSize: pageSize
        )

        // 초과분은 cap으로 잘려 명령 수·높이가 cap과 같다 (backing layer 폭발 방어, P1)
        expect(overCap.paintList.commands.count) == atCap.paintList.commands.count
        expect(overCap.contentHeight) == atCap.contentHeight
        expect(underCap.paintList.commands.count) < atCap.paintList.commands.count
    }
}

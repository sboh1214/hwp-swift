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

    /// 긴 작성자명은 고정 1행 헤더의 남은 폭에 맞춰 한 줄로 절단된다 — wrapping해
    /// trailing/본문과 겹치거나 풍선을 벗어나지 않는다 (R51 #4).
    func testLongMemoAuthorTruncatedToSingleLine() {
        let longAuthor = String(repeating: "가", count: 100)
        let balloon = HwpMemoPanelPainter.Balloon(
            anchorY: 100, author: longAuthor, dateText: "2026/07/16 00:00", body: "body"
        )
        let panel = HwpMemoPanelPainter.panel(
            balloons: [balloon], pageSize: CGSize(width: 595, height: 842)
        )

        let authorText = panel.paintList.commands.compactMap { command -> String? in
            if case let .drawText(attributedString, _, _) = command,
               attributedString.string.contains("가")
            {
                return attributedString.string
            }
            return nil
        }.first
        expect(authorText).toNot(beNil())
        expect(authorText?.count ?? longAuthor.count).to(beLessThan(longAuthor.count))
    }
}

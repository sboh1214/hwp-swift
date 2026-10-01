import CoreGraphics
import Nimble

/// `CGRect` 네 성분(x·y·폭·높이)을 오차 안에서 비교한다 — 테두리 획 두께는 장치 단위(0.12pt)로
/// 반올림해(#245) 모서리 좌표에 이진 소수 잡음이 남으므로 `equal` 대신 쓴다.
func beCloseTo(_ expected: CGRect, within delta: CGFloat = 1e-9) -> Matcher<CGRect> {
    Matcher.define("be close to <\(expected)> (within \(delta))") { actualExpression, message in
        guard let actual = try actualExpression.evaluate() else {
            return MatcherResult(status: .fail, message: message.appendedBeNilHint())
        }
        let close = abs(actual.minX - expected.minX) <= delta
            && abs(actual.minY - expected.minY) <= delta
            && abs(actual.width - expected.width) <= delta
            && abs(actual.height - expected.height) <= delta
        return MatcherResult(bool: close, message: message.appended(details: "got <\(actual)>"))
    }
}

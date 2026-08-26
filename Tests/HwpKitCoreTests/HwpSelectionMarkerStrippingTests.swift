import CoreText
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

/// U+FFFC 마커 run 제거(`strippingControlMarkerRuns`) 자체의 계약 — 마커 전용
/// 속성 소멸, 마커를 감싼 링크의 범위, 선형 복잡도. 그 결과를 조립 경로가
/// 무엇으로 만드는지는 `HwpSelectionGeometryAttributedTests`.
final class HwpSelectionMarkerStrippingTests: XCTestCase {
    private let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func attributed(
        _ text: String, extra: [NSAttributedString.Key: Any] = [:]
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
        ]
        for (key, value) in extra {
            attributes[key] = value
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    func testMarkerRemovalDropsMarkerOnlyAttributes() {
        // 마커 문자가 사라지면 run delegate·controlIndex 같은 마커 전용
        // 속성도 함께 사라지고, 남은 글자에는 어떤 잔재도 없어야 한다.
        let mutable = NSMutableAttributedString()
        mutable.append(attributed("a"))
        mutable.append(attributed("\u{FFFC}", extra: [
            HwpAttributedStringKey.controlIndex: NSNumber(value: 3),
            HwpAttributedStringKey.inlineObjectHeight: NSNumber(value: 24.0),
        ]))
        mutable.append(attributed("b"))

        let stripped = HwpSelectionGeometry.strippingControlMarkerRuns(mutable)

        expect(stripped.string) == "ab"
        var found = false
        stripped.enumerateAttribute(
            HwpAttributedStringKey.controlIndex,
            in: NSRange(location: 0, length: stripped.length)
        ) { value, _, _ in
            found = found || value != nil
        }
        expect(found) == false
    }

    func testMarkerRemovalContractsWrappingHyperlinkRange() {
        // 링크가 U+FFFC run을 감싸도(필드가 개체를 포함) 마커를 지운 뒤
        // 링크 범위가 남은 글자에 정확히 붙는다 — 번지거나 잘리면 안 된다.
        let mutable = NSMutableAttributedString()
        mutable.append(attributed("전"))
        let linked = NSMutableAttributedString()
        linked.append(attributed("링\u{FFFC}크"))
        linked.addAttribute(
            HwpAttributedStringKey.hyperlink,
            value: "https://example.com",
            range: NSRange(location: 0, length: linked.length)
        )
        mutable.append(linked)
        mutable.append(attributed("후"))

        let stripped = HwpSelectionGeometry.strippingControlMarkerRuns(mutable)

        expect(stripped.string) == "전링크후"
        var linkRange = NSRange(location: NSNotFound, length: 0)
        let value = stripped.attribute(
            HwpAttributedStringKey.hyperlink, at: 1,
            longestEffectiveRange: &linkRange,
            in: NSRange(location: 0, length: stripped.length)
        )
        expect(value as? String) == "https://example.com"
        expect(linkRange) == NSRange(location: 1, length: 2)
    }

    /// 이전 형태는 마커마다 `deleteCharacters`를 불러 남은 접미를 매번 밀었다
    /// (2026-08-26 로컬 릴리스, 마커당 텍스트 4자: 2,500개 0.36초 · 5,000개
    /// 1.48초 · 10,000개 5.90초 · 20,000개 23.49초 — 배가 될 때마다 4배).
    /// 복사가 `@MainActor`에서 도는 만큼 그대로 화면이 멈춘다.
    ///
    /// `mutableString.replaceOccurrences`로는 못 고친다 — 상수만 215배 작을 뿐
    /// 여전히 제자리 삭제라 4배씩 는다 (10,000개 0.027초 → 80,000개 1.82초).
    /// 비마커 구간 append만 2.0배/배로 선형이다 (10,000개 0.017초 → 80,000개
    /// 0.129초).
    func testMarkerStrippingStaysLinear() {
        let full = ProcessInfo.processInfo.environment["HWP_PERF"] != nil
        let markers = full ? 40000 : 5000
        let source = NSMutableAttributedString()
        for index in 0 ..< markers {
            source.append(attributed("본문\(index % 10) "))
            source.append(attributed("\u{FFFC}", extra: [
                HwpAttributedStringKey.controlIndex: NSNumber(value: index),
            ]))
        }

        let clock = ContinuousClock()
        let start = clock.now
        let stripped = HwpSelectionGeometry.strippingControlMarkerRuns(source)
        let elapsed = clock.now - start

        expect(stripped.length) == markers * 4
        expect(stripped.string.contains("\u{FFFC}")) == false
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print("HWP_PERF marker-strip: N=\(markers) time=\(String(format: "%.3f", seconds))s")
        // 임계 = 선형 실측 + 넉넉한 여유. 이차로 되돌아가면 넘는다 —
        // 이전 형태는 기본 N=5,000에서 이미 1.48초다.
        expect(seconds) < (full ? 2.0 : 0.5)
    }
}

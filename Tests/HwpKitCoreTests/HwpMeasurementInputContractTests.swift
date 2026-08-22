@testable import CoreHwp
import Foundation
@testable import HwpKitCore
import Nimble
import XCTest

#if canImport(CoreText)
    import CoreText

    /// 측정 입력 계약 (#80 조각 3): `HwpParagraphLayout.layout`은 문단 스타일이
    /// **부착된** 문자열을 받아 그대로 framesetting한다.
    ///
    /// 계약이 깨지는 길은 둘뿐이다 — 호출부가 부착을 빠뜨리거나, 부착과 측정이
    /// **서로 다른 paraShape**를 해석하거나. 여기 두 테스트가 각각을 겨냥한다.
    final class HwpMeasurementInputContractTests: XCTestCase {
        /// paraShape 표가 **통째로 빈** 문서에서도 부착(`attachParagraphStyle`)과
        /// 측정이 같은 기본 shape를 쓴다.
        ///
        /// 측정이 부착본을 그대로 framesetting하게 된 뒤로 이 축은 이론이 아니다 —
        /// 부착이 `paraShape(for:)`(nil 가능)로 돌아가면 스타일이 통째로 생략되고,
        /// 측정은 강제 줄 높이를 잃어 CT 자연 줄 높이로 떨어진다. 저장소 픽스처
        /// 33종 중 이 경로를 타는 것이 **0개**라 합성으로만 잡을 수 있다
        /// (되돌리면 줄 피치가 16.0 → 12.44pt로 떨어져 빨개진다 — 2026-08-22 실측).
        func testEmptyParaShapeTableStillAppliesDefaultParagraphStyle() throws {
            let index = Self.emptyIndex()
            expect(index.paraShape(id: 0)).to(beNil())

            let paragraph = try HwpSynthetic.textParagraph(
                String(repeating: "가나다라마바사아자차카타파하 ", count: 8)
            )
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: paragraph)
            // index.paraShape(for:)는 nil인데도 부착이 생략되지 않는다.
            expect(HwpLineBreaker.paragraphStyle(in: built, at: 0)).toNot(beNil())

            let width: CGFloat = 120
            let frame = HwpParagraphLayout().layout(
                attributedString: built,
                paraShape: index.paraShapeOrDefault(for: paragraph),
                columnWidth: width
            )
            expect(frame.lines.count).to(beGreaterThanOrEqualTo(3))
            // 기본 shape는 비율 160%라 줄 전진량이 글자 크기의 1.6배로 강제된다.
            // 스타일이 안 붙었다면 CT 자연 줄 높이(≈1.2배)로 떨어진다.
            let expectedPitch = HwpParagraphLayout.ParagraphMetrics
                .maxFontSize(in: built) * 1.6
            expect(expectedPitch).to(beGreaterThan(0))
            let perLine = frame.totalHeight / CGFloat(frame.lines.count)
            expect(perLine).to(beCloseTo(expectedPitch, within: expectedPitch * 0.1))

            // 그리고 그 부착본에서 측정과 렌더가 같은 줄로 갈린다.
            let drawn = HwpDrawnTextLayout.lines(
                attributedString: built, origin: .zero, lineWidth: width
            )
            expect(frame.lines.map(\.attributedRange)) == drawn.map(\.stringRange)
        }

        /// 부착을 빠뜨린 입력은 **조용히** CT 기본값으로 조판된다 — 계약 위반이
        /// 어떤 모습인지 못박는다. 이 테스트가 초록인 한, 위 테스트가 재는 차이는
        /// "부착이 실제로 조판에 닿는다"의 증거다.
        func testUnstyledInputFallsBackToCoreTextDefaults() throws {
            let index = Self.emptyIndex()
            let paragraph = try HwpSynthetic.textParagraph(
                String(repeating: "가나다라마바사아자차카타파하 ", count: 8)
            )
            let built = HwpTextRunBuilder(index: index, fontResolver: .testDeterministic)
                .build(paragraph: paragraph)
            let bare = NSMutableAttributedString(attributedString: built)
            bare.removeAttribute(
                kCTParagraphStyleAttributeName as NSAttributedString.Key,
                range: NSRange(location: 0, length: bare.length)
            )

            let shape = index.paraShapeOrDefault(for: paragraph)
            let styled = HwpParagraphLayout().layout(
                attributedString: built, paraShape: shape, columnWidth: 120
            )
            let unstyled = HwpParagraphLayout().layout(
                attributedString: bare, paraShape: shape, columnWidth: 120
            )

            expect(styled.lines.count) == unstyled.lines.count
            // 줄바꿈은 같아도 전진량이 다르다 — 강제 줄 높이가 부착본에만 있다.
            expect(unstyled.totalHeight).to(beLessThan(styled.totalHeight))
        }

        /// id 매핑이 통째로 빈 인덱스. `HwpIndex(from: HwpFile())`는 빈 문서
        /// **템플릿**이라 paraShape id 0을 갖고 있어 이 축을 못 만든다.
        private static func emptyIndex() -> HwpIndex {
            HwpIndex(
                charShapes: [:], paraShapes: [:], borderFills: [:], tabDefs: [:],
                styles: [:], bullets: [:], numberings: [:], binData: [:],
                faceNamesKorean: [:], faceNamesEnglish: [:], faceNamesChinese: [:],
                faceNamesJapanese: [:], faceNamesEtc: [:], faceNamesSymbol: [:],
                faceNamesUser: [:]
            )
        }
    }
#endif

import CoreGraphics
import Foundation

/// 검색 하이라이트 색.
///
/// 계층을 통과하는 색 타입이 `HwpRGBColor`인 이유: `CGColor`는 Hashable이
/// 아니라 SwiftUI 값 상태로 들고 다닐 수 없고, `NSColor`/`UIColor`는 HwpKit이
/// 만들 수 없다 (AppKit/UIKit 직접 import 금지).
public struct HwpSearchHighlightStyle: Sendable, Hashable {
    /// 전체 매치 색.
    public var matchColor: HwpRGBColor
    /// 현재 매치 색 — 전체 매치 위에 겹쳐 칠한다.
    public var currentMatchColor: HwpRGBColor

    public init(matchColor: HwpRGBColor, currentMatchColor: HwpRGBColor) {
        self.matchColor = matchColor
        self.currentMatchColor = currentMatchColor
    }

    /// 고정 sRGB.
    ///
    /// 동적 시스템 색을 쓰지 않는 이유: `HwpRGBColor.cgColor`가 변환 시점의
    /// 외형으로 굳는데 `HwpKitNative`에는 appearance/trait 변경 훅이 하나도
    /// 없어, 다크 모드로 전환해도 낡은 색이 남는다. OS 테마와 정확히 어울리지
    /// 않는 대신 어느 모드에서도 틀리지 않는 쪽을 택했다. 호스트가 자기
    /// 테마에 맞추고 싶으면 이 값을 갈아 끼우면 된다.
    public static let `default` = HwpSearchHighlightStyle(
        matchColor: HwpRGBColor(red: 1.0, green: 0.84, blue: 0.20, alpha: 0.45),
        currentMatchColor: HwpRGBColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.70)
    )
}

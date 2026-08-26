import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import QuartzCore

/// 뷰 레이어 트리 회귀 스냅샷 (#125) — 자식 순서·타입·frame·zPosition·
/// contentsScale 조합을 텍스트 한 장으로 고정한다. 개별 단언(오버레이 부착·
/// 재사용·z-순서)은 각자 있지만, 검색 하이라이트 (#75)·선택 (#5)·메모 패널
/// (#8)이 겹친 **조합 전체**를 한 번에 잠그는 것은 이 스냅샷뿐이다.
///
/// macOS·iOS가 같은 시나리오 문서로 **같은 기대 트리**를 단언한다 — 두 뷰의
/// 레이어 구성이 대칭이라는 반복 규약("macOS와 대칭")이 여기서 검증된다.
@MainActor
enum HwpLayerTreeSnapshot {
    /// 시나리오 문서: 3쪽 × "alpha beta alpha" 텍스트 블록.
    /// - 0쪽: 기본 메모 패널 (contentHeight 0 → 페이지 높이)
    /// - 1쪽: 페이지보다 긴 메모 패널 (contentHeight 1000 — #8 오버플로 행)
    /// - 2쪽: 패널 없음 (좁은 행 → 행 중앙 정렬 x=60)
    static func document() -> HwpDocument {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let pages = (0 ..< 3).map { index in
            HwpPage(
                size: CGSize(width: 595, height: 842),
                margins: HwpPageMargins(top: 0, left: 0, bottom: 0, right: 0),
                blocks: [AnyHwpBlock(
                    frame: CGRect(x: 50, y: 100, width: 400, height: 20),
                    kind: .text,
                    attributedString: NSAttributedString(
                        string: "alpha beta alpha",
                        attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                    )
                )],
                pageNumber: index + 1,
                memoPanel: memoPanel(forPage: index)
            )
        }
        return HwpDocument(
            pages: pages,
            metadata: HwpDocumentMetadata(pageCount: pages.count),
            unsupportedElements: []
        )
    }

    private static func memoPanel(forPage index: Int) -> HwpMemoPanel? {
        switch index {
        case 0: HwpMemoPanel(width: 120, paintList: HwpPaintList(commands: []))
        case 1: HwpMemoPanel(
                width: 120,
                paintList: HwpPaintList(commands: []),
                contentHeight: 1000
            )
        default: nil
        }
    }

    /// "alpha" 검색 (전 쪽 매치 + 0쪽 현재 매치) 후 0쪽 0..5 선택을 건 트리.
    /// 부착 순서는 검색 매치 (z10) → 현재 매치 (z20) → 선택 (z30)이고,
    /// 오버레이 frame은 페이지 레이어 로컬 좌표 (= bounds)다.
    static let expectedTree = """
    HwpPageLayer frame=(0, 0, 595, 842) scale=1x z=0
      CAShapeLayer frame=(0, 0, 595, 842) scale=1x z=10
      CAShapeLayer frame=(0, 0, 595, 842) scale=1x z=20
      CAShapeLayer frame=(0, 0, 595, 842) scale=1x z=30
    HwpPageLayer frame=(595, 0, 120, 842) scale=1x z=0
    HwpPageLayer frame=(0, 866, 595, 842) scale=1x z=0
      CAShapeLayer frame=(0, 0, 595, 842) scale=1x z=10
    HwpPageLayer frame=(595, 866, 120, 1000) scale=1x z=0
    HwpPageLayer frame=(60, 1890, 595, 842) scale=1x z=0
      CAShapeLayer frame=(0, 0, 595, 842) scale=1x z=10
    """

    /// `root`의 sublayer 트리를 들여쓰기 텍스트로 직렬화한다. root 자체는 적지
    /// 않는다 — 뷰 backing layer의 구체 타입은 OS 버전 종속이다.
    ///
    /// contentsScale은 절대값이 아니라 **기준 배율의 배수**로 적는다: 절대값은
    /// 러너 스크린 (macOS backingScaleFactor)·시뮬레이터 트레잇 (iOS
    /// displayScale)에 따라 갈려 스냅샷이 머신 종속이 된다. frame은 정수
    /// 반올림 — 이 시나리오의 기하는 전부 정수라 관측 편차 흡수용이다.
    static func describe(sublayersOf root: CALayer, baseScale: CGFloat) -> String {
        describeLines(sublayersOf: root, baseScale: baseScale, indent: "")
            .joined(separator: "\n")
    }

    private static func describeLines(
        sublayersOf layer: CALayer,
        baseScale: CGFloat,
        indent: String
    ) -> [String] {
        (layer.sublayers ?? []).flatMap { sublayer in
            [indent + describeLine(sublayer, baseScale: baseScale)]
                + describeLines(
                    sublayersOf: sublayer, baseScale: baseScale, indent: indent + "  "
                )
        }
    }

    private static func describeLine(_ layer: CALayer, baseScale: CGFloat) -> String {
        let frame = layer.frame
        let scale = baseScale > 0 ? layer.contentsScale / baseScale : layer.contentsScale
        return String(
            format: "%@ frame=(%.0f, %.0f, %.0f, %.0f) scale=%gx z=%g",
            String(describing: type(of: layer)),
            frame.minX.rounded(), frame.minY.rounded(),
            frame.width.rounded(), frame.height.rounded(),
            scale, layer.zPosition
        )
    }
}

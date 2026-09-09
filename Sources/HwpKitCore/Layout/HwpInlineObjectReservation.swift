import CoreGraphics
import CoreHwp
import CoreText
import Foundation

public extension HwpAttributedStringKey {
    /// treatAsChar 개체 마커가 예약한 **폭**의 저장값 (NSNumber, 표 70 width).
    /// `inlineObjectWidthBasis`와 짝으로만 붙는다.
    static let inlineObjectWidthRaw = NSAttributedString.Key("hwp.inlineObjectWidthRaw")
    /// 그 저장값의 크기 기준 (NSNumber, `HwpCommonCtrlObjectWidthRelativeTo` rawValue)
    /// — **단 폭에 딸린 기준('단'·'문단')일 때만** 붙는다.
    ///
    /// 예약 폭이 단 폭의 함수인 개체는 문단을 처음 잰 단의 폭으로 예약돼 문자열에
    /// 실린다. 그런데 paint 쪽(`HwpPaginator.objectSize`)은 개체가 **놓이는** 단으로
    /// 다시 푸므로, 문단 조각이 폭이 다른 단으로 이월되면 예약과 그림 크기가 갈려
    /// 개체가 뒤 글자를 덮는다 (#164 리뷰). 이 짝이 그 자리에서 예약을 다시 풀
    /// 열쇠다 — `HwpInlineObjectReservation.rescaledForColumn`.
    static let inlineObjectWidthBasis = NSAttributedString.Key("hwp.inlineObjectWidthBasis")
}

/// treatAsChar 개체의 줄 공간 예약 값 (CTRunDelegate refCon)
private final class HwpInlineObjectMetrics {
    let width: CGFloat
    let ascent: CGFloat

    init(width: CGFloat, ascent: CGFloat) {
        self.width = width
        self.ascent = ascent
    }
}

/// treatAsChar 개체의 줄 공간 예약 — 예약 값(run delegate)을 만들고, 단 폭에
/// 딸린 예약 폭을 다른 단 기하로 다시 푼다.
enum HwpInlineObjectReservation {
    /// treatAsChar 개체 크기만큼 줄 공간을 예약하는 CTRunDelegate를 만든다.
    static func runDelegate(width: CGFloat, height: CGFloat) -> CTRunDelegate? {
        let metrics = HwpInlineObjectMetrics(width: width, ascent: height)
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { pointer in
                Unmanaged<HwpInlineObjectMetrics>.fromOpaque(pointer).release()
            },
            getAscent: { pointer in
                Unmanaged<HwpInlineObjectMetrics>.fromOpaque(pointer)
                    .takeUnretainedValue().ascent
            },
            getDescent: { _ in 0 },
            getWidth: { pointer in
                Unmanaged<HwpInlineObjectMetrics>.fromOpaque(pointer)
                    .takeUnretainedValue().width
            }
        )
        return CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(metrics).toOpaque())
    }

    /// 마커에 실을 예약 폭 열쇠 — 폭 기준이 단 폭에 딸릴 때만 값이 있다.
    /// 개체 요소 detail로 폴백한 폭(`HwpTextRunBuilder.inlineObjectReservation`)은 절대값
    /// (HWPUNIT)이라 다시 풀 게 없으므로 열쇠를 싣지 않는다.
    static func widthKeyAttributes(
        raw: UInt32,
        basis: CoreHwp.HwpCommonCtrlObjectWidthRelativeTo?
    ) -> [NSAttributedString.Key: Any] {
        guard let basis, basis == .column || basis == .paragraph else { return [:] }
        return [
            HwpAttributedStringKey.inlineObjectWidthRaw: NSNumber(value: raw),
            HwpAttributedStringKey.inlineObjectWidthBasis: NSNumber(value: basis.rawValue),
        ]
    }

    /// 단 폭에 딸린 예약 폭을 `resolver` 기하로 다시 푼 사본 — 다시 풀 마커가 없으면
    /// 원본 그대로다 (사본을 뜨지 않는다).
    ///
    /// 조각이 폭이 다른 단으로 이월될 때, 앵커를 그 단 폭으로 다시 조판하기
    /// (`HwpPaginator.fragmentAnchorLines`) **전에** 문자열을 이걸로 갈아야 예약·조판·
    /// paint가 한 폭을 본다. 렌더 문자열과 앵커 문맥이 같은 사본이어야 마커 x가
    /// 그려진 자리와 맞는다.
    ///
    /// 높이는 다시 풀지 않는다 — 폭과 달리 높이 기준(표 70)엔 '단'이 없어
    /// (종이·쪽·절대) 단 폭과 무관하다.
    static func rescaledForColumn(
        _ string: NSAttributedString,
        resolver: HwpObjectSizeResolver
    ) -> NSAttributedString {
        var rescaled: NSMutableAttributedString?
        string.enumerateAttribute(
            HwpAttributedStringKey.inlineObjectWidthBasis,
            in: NSRange(location: 0, length: string.length)
        ) { value, range, _ in
            guard let basisValue = value as? NSNumber,
                  let basis = CoreHwp.HwpCommonCtrlObjectWidthRelativeTo(
                      rawValue: basisValue.intValue
                  ),
                  let raw = string.attribute(
                      HwpAttributedStringKey.inlineObjectWidthRaw,
                      at: range.location, effectiveRange: nil
                  ) as? NSNumber,
                  let delegate = runDelegate(
                      width: resolver.width(raw.uint32Value, basis: basis),
                      height: reservedHeight(of: string, at: range.location)
                  )
            else { return }
            let target = rescaled ?? NSMutableAttributedString(attributedString: string)
            rescaled = target
            target.addAttribute(
                kCTRunDelegateAttributeName as NSAttributedString.Key,
                value: delegate,
                range: range
            )
        }
        return rescaled ?? string
    }

    /// 마커가 예약한 줄 공간 높이 — 빌더가 `inlineObjectHeight`로 실어 둔 값이다.
    private static func reservedHeight(of string: NSAttributedString, at location: Int) -> CGFloat {
        guard let height = string.attribute(
            HwpAttributedStringKey.inlineObjectHeight, at: location, effectiveRange: nil
        ) as? NSNumber else { return 0 }
        return CGFloat(height.doubleValue)
    }
}

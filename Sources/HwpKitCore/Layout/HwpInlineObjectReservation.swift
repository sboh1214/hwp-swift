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

extension HwpAttributedStringKey {
    /// 예약 폭에 든 좌우 바깥 여백 합 (NSNumber, pt) — 폭 열쇠(`inlineObjectWidthRaw`·
    /// `inlineObjectWidthBasis`)와 함께만 붙고, 여백이 있을 때만 붙는다. 예약 폭을 다른 단
    /// 기하로 다시 풀 때 개체 폭에 이 값을 다시 더한다 (#193).
    static let inlineObjectWidthMargin = NSAttributedString.Key("hwp.inlineObjectWidthMargin")
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
    /// `horizontalMargin`은 예약 폭에 든 좌우 바깥 여백 합이다 (#193) — 다시 풀 때 더한다.
    static func widthKeyAttributes(
        raw: UInt32,
        basis: CoreHwp.HwpCommonCtrlObjectWidthRelativeTo?,
        horizontalMargin: CGFloat = 0
    ) -> [NSAttributedString.Key: Any] {
        guard let basis, basis == .column || basis == .paragraph else { return [:] }
        var attributes: [NSAttributedString.Key: Any] = [
            HwpAttributedStringKey.inlineObjectWidthRaw: NSNumber(value: raw),
            HwpAttributedStringKey.inlineObjectWidthBasis: NSNumber(value: basis.rawValue),
        ]
        if horizontalMargin > 0 {
            attributes[HwpAttributedStringKey.inlineObjectWidthMargin] = NSNumber(
                value: Double(horizontalMargin)
            )
        }
        return attributes
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
    /// (종이·쪽·절대) 단 폭과 무관하다. 다만 delegate는 폭·높이를 함께 나르므로 마커가
    /// 이미 실어 둔 예약 높이(`inlineObjectHeight`)를 **그 마커에서** 다시 읽어 얹는다.
    /// 글자처럼 취급 표의 예약 높이는 단 폭의 함수라(#214) 호출부가 이 뒤에
    /// `withReservedHeights`로 따로 다시 잡는다 (`HwpPaginator.placedFragment`).
    static func rescaledForColumn(
        _ string: NSAttributedString,
        resolver: HwpObjectSizeResolver
    ) -> NSAttributedString {
        var rescaled: NSMutableAttributedString?
        string.enumerateAttribute(
            HwpAttributedStringKey.inlineObjectWidthBasis,
            in: NSRange(location: 0, length: string.length)
        ) { value, range, _ in
            guard value != nil else { return }
            // `enumerateAttribute`는 값이 같은 이웃 run을 **한 범위로 합친다** — 크기 기준이
            // 같은 마커가 잇달아 있으면(연속 개체) 한 범위로 온다. 그래서 글자 단위로
            // 되짚어 개체마다 자기 치수를 지킨다 (PR 리뷰: 범위 첫 마커의 치수를 통째로
            // 얹어 뒤 개체의 예약 폭·높이를 덮었다). 되짚기의 근거는 **폭 열쇠를 나르는
            // 글자가 U+FFFC 한 글자**라는 것이고, 그 불변식은 마커 방출·열쇠 부착이
            // `HwpTextRunBuilder`의 컨트롤 마커 방출 한 곳뿐이라는 데서 온다 — 마커를 여러
            // 글자로 바꾸는 변경이 오면 여기도 함께 손봐야 한다.
            for location in range.location ..< NSMaxRange(range) {
                guard let delegate = resolvedDelegate(
                    of: string, at: location, resolver: resolver
                ) else { continue }
                let target = rescaled ?? NSMutableAttributedString(attributedString: string)
                rescaled = target
                target.addAttribute(
                    kCTRunDelegateAttributeName as NSAttributedString.Key,
                    value: delegate,
                    range: NSRange(location: location, length: 1)
                )
            }
        }
        return rescaled ?? string
    }

    /// 마커 한 글자의 예약을 `resolver` 기하로 다시 푼 run delegate — 폭 열쇠가 온전하지
    /// 않으면 nil(그 마커는 그대로 둔다). 높이는 빌더가 실어 둔 `inlineObjectHeight`(바깥
    /// 여백 포함)이고, 폭은 다시 푼 개체 폭 + 좌우 바깥 여백(`inlineObjectWidthMargin`)이다.
    private static func resolvedDelegate(
        of string: NSAttributedString,
        at location: Int,
        resolver: HwpObjectSizeResolver
    ) -> CTRunDelegate? {
        let attributes = string.attributes(at: location, effectiveRange: nil)
        guard let basisValue = attributes[
            HwpAttributedStringKey.inlineObjectWidthBasis
        ] as? NSNumber,
            let basis = CoreHwp.HwpCommonCtrlObjectWidthRelativeTo(
                rawValue: basisValue.intValue
            ),
            let raw = attributes[HwpAttributedStringKey.inlineObjectWidthRaw] as? NSNumber
        else { return nil }
        let height = attributes[HwpAttributedStringKey.inlineObjectHeight] as? NSNumber
        let margin = attributes[HwpAttributedStringKey.inlineObjectWidthMargin] as? NSNumber
        return runDelegate(
            width: resolver.width(raw.uint32Value, basis: basis)
                + (margin.map { CGFloat($0.doubleValue) } ?? 0),
            height: height.map { CGFloat($0.doubleValue) } ?? 0
        )
    }

    /// 예약을 가진 개체 마커(U+FFFC + `controlIndex` + 예약 높이)의 컨트롤 서수들 — 문서 순서.
    static func reservedMarkerControlIndices(in string: NSAttributedString) -> [Int] {
        var ordinals: [Int] = []
        forEachReservedMarker(in: string) { ordinal, _, _ in ordinals.append(ordinal) }
        return ordinals
    }

    /// 개체 마커의 예약 높이를 `outerHeights`(controlIndex → 바깥 상자 높이, pt)로 바꾼 사본
    /// (#214) — 폭은 마커가 이미 예약한 값 그대로다. 예약이 없는 마커(예약 높이를 싣지 않은
    /// 폭 0 마커)는 예약을 새로 만들지 않고, 값이 같은 마커는 건드리지 않는다. 바꿀 것이
    /// 없으면 원본 그대로다 (사본을 뜨지 않는다).
    static func withReservedHeights(
        _ string: NSAttributedString,
        outerHeights: [Int: CGFloat]
    ) -> NSAttributedString {
        guard !outerHeights.isEmpty else { return string }
        var updated: NSMutableAttributedString?
        forEachReservedMarker(in: string) { ordinal, location, reservedHeight in
            guard let height = outerHeights[ordinal], height != reservedHeight,
                  let width = reservedWidth(of: string, at: location)
            else { return }
            let target = updated ?? NSMutableAttributedString(attributedString: string)
            updated = target
            let range = NSRange(location: location, length: 1)
            if let delegate = runDelegate(width: width, height: height) {
                target.addAttribute(
                    kCTRunDelegateAttributeName as NSAttributedString.Key,
                    value: delegate,
                    range: range
                )
            }
            target.addAttribute(
                HwpAttributedStringKey.inlineObjectHeight,
                value: NSNumber(value: Double(height)), range: range
            )
        }
        return updated ?? string
    }

    /// 예약 높이(`inlineObjectHeight`)를 실은 U+FFFC 마커마다 (컨트롤 서수, 위치, 예약 높이).
    private static func forEachReservedMarker(
        in string: NSAttributedString,
        _ body: (Int, Int, CGFloat) -> Void
    ) {
        let text = string.string as NSString
        string.enumerateAttribute(
            HwpAttributedStringKey.inlineObjectHeight,
            in: NSRange(location: 0, length: string.length)
        ) { value, range, _ in
            guard let reserved = value as? NSNumber else { return }
            // 값이 같은 이웃 마커는 한 범위로 합쳐 오므로 글자 단위로 되짚는다
            // (`rescaledForColumn`과 같은 이유).
            for location in range.location ..< NSMaxRange(range)
                where text.character(at: location) == 0xFFFC
            {
                guard let ordinal = string.attribute(
                    HwpAttributedStringKey.controlIndex, at: location, effectiveRange: nil
                ) as? NSNumber else { continue }
                body(ordinal.intValue, location, CGFloat(reserved.doubleValue))
            }
        }
    }

    /// 마커 한 글자의 run delegate가 예약한 폭.
    private static func reservedWidth(of string: NSAttributedString, at location: Int) -> CGFloat? {
        guard let value = string.attribute(
            kCTRunDelegateAttributeName as NSAttributedString.Key, at: location, effectiveRange: nil
        ) else { return nil }
        let reference = value as CFTypeRef
        guard CFGetTypeID(reference) == CTRunDelegateGetTypeID() else { return nil }
        let delegate = unsafeBitCast(reference, to: CTRunDelegate.self)
        return Unmanaged<HwpInlineObjectMetrics>.fromOpaque(CTRunDelegateGetRefCon(delegate))
            .takeUnretainedValue().width
    }
}

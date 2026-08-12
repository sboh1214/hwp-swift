import CoreGraphics
import Foundation

public protocol HwpBlock: Sendable {
    var frame: CGRect { get }
    var kind: HwpBlockKind { get }
}

public enum HwpBlockKind: String, Sendable, Hashable {
    case text, image, shape, table, textbox, footnote, placeholder
}

/// 블록이 본문 흐름인지 페이지 크롬 (머리말/꼬리말/쪽 번호)인지 —
/// 텍스트 선택·복사는 크롬을 건너뛴다.
public enum HwpBlockRole: String, Sendable, Hashable {
    case body, pageChrome
}

/// 겹치는 개체의 페인트/히트 평면 (표 70 textWrap). 블록 배열은 문서 논리
/// 순서로 두고, 페인트·히트만 이 평면 → zOrder → 삽입순으로 정렬한다 —
/// behind는 텍스트 뒤, inFront는 텍스트 앞에 그려지고 히트된다 (#8/#9/#10).
public enum HwpBlockPaintPlane: Int, Sendable, Hashable, Comparable {
    case behind = 0
    case normal = 1
    case front = 2
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 렌더 모델 동등성이 쓰는 **문자열 동일성** 판정.
///
/// Swift `String ==` 는 정규 동치라 NFC "가"(UTF-16 1 단위)와 NFD "가"(2 단위)를
/// 같다고 본다. 그런데 `HwpTextPosition.characterOffset` 은 UTF-16 오프셋이라
/// 그 둘 사이에서 뒤 오프셋이 전부 밀린다 — 두 문서를 "같은 내용"으로 접으면
/// (`HwpGeometryChange.isEquivalentRefresh`) 재스캔이 생략된 채 낡은 오프셋이
/// 새 문자열에 적용돼 하이라이트·스크롤이 어긋난다 (#75 리뷰 9차).
/// `NSString` 동등성이 그 코드 단위 비교다.
///
/// `hash` 는 그대로 Swift 문자열 해시를 쓴다 — 이쪽이 더 **엄격**하므로
/// (동일 ⟹ 정규 동치 ⟹ 같은 해시) Hashable 계약이 유지된다.
enum HwpTextIdentity {
    static func isIdentical(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return (lhs as NSString).isEqual(to: rhs)
    }
}

public struct AnyHwpBlock: HwpBlock, @unchecked Sendable, Hashable {
    public let frame: CGRect
    public let kind: HwpBlockKind
    public let attributedString: NSAttributedString?
    public let hyperlinkURL: String?
    /// 블록 종류별 상세 레이아웃 결과 (표 셀 grid, 도형 path, 이미지 참조 등)
    public let payload: HwpBlockPayload?
    /// 이 블록이 유래한 CoreHwp 모델 참조 (편집 대비)
    public let source: HwpBlockSource?
    public let role: HwpBlockRole
    /// 페인트/히트 평면 (behind/normal/front) — 블록 배열 순서는 논리 순서로
    /// 두고 페인트·히트만 이 값으로 정렬한다 (#8/#10).
    public let paintPlane: HwpBlockPaintPlane
    /// 겹치는 개체의 z-순서 (Send Backward/Forward) — 같은 평면 안 정렬 기준 (#9).
    public let zOrder: Int32

    public init(
        frame: CGRect,
        kind: HwpBlockKind,
        attributedString: NSAttributedString? = nil,
        hyperlinkURL: String? = nil,
        payload: HwpBlockPayload? = nil,
        source: HwpBlockSource? = nil,
        role: HwpBlockRole = .body,
        paintPlane: HwpBlockPaintPlane = .normal,
        zOrder: Int32 = 0
    ) {
        self.frame = frame
        self.kind = kind
        // 호출자가 소유한 NSMutableAttributedString이 @unchecked Sendable & Hashable
        // 값 안에서 뒤에 변형되면 렌더/해시가 태스크 간 어긋난다 — immutable 복사로
        // 소유권을 끊는다 (HwpLaidOutParagraph 등 다른 레이아웃 모델과 동일).
        self.attributedString = attributedString.map { NSAttributedString(attributedString: $0) }
        self.hyperlinkURL = hyperlinkURL
        self.payload = payload
        self.source = source
        self.role = role
        self.paintPlane = paintPlane
        self.zOrder = zOrder
    }

    /// 반복 표 머리행 클론 표식. `attributedString` 의 **속성**이라 문자열
    /// 비교로는 안 잡히는데, 검색 목록 dedup 이 이 값으로 판정한다
    /// (`HwpTextSearcher`). 동등성에서 빠지면 이 플래그만 뒤집힌 재전달이
    /// "내용이 같은 재전달"로 접혀 (`HwpSearchController.geometryDidChange`)
    /// 재스캔이 생략되고, 목록·현재 매치가 옛 분류에 머문다 (#75 리뷰 7차).
    /// 판정은 선택·검색과 **같은 술어**를 쓴다 — 각자 속성 키를 읽으면 갈린다.
    var isRepeatedTableHeaderClone: Bool {
        attributedString.map(HwpSelectionGeometry.isRepeatedHeaderClone) ?? false
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
        hasher.combine(attributedString?.string)
        hasher.combine(isRepeatedTableHeaderClone)
        hasher.combine(hyperlinkURL)
        hasher.combine(payload)
        hasher.combine(source)
        hasher.combine(role)
        hasher.combine(paintPlane)
        hasher.combine(zOrder)
    }

    public static func == (lhs: AnyHwpBlock, rhs: AnyHwpBlock) -> Bool {
        lhs.kind == rhs.kind
            && lhs.frame == rhs.frame
            && HwpTextIdentity.isIdentical(
                lhs.attributedString?.string, rhs.attributedString?.string
            )
            && lhs.isRepeatedTableHeaderClone == rhs.isRepeatedTableHeaderClone
            && lhs.hyperlinkURL == rhs.hyperlinkURL
            && lhs.payload == rhs.payload
            && lhs.source == rhs.source
            && lhs.role == rhs.role
            && lhs.paintPlane == rhs.paintPlane
            && lhs.zOrder == rhs.zOrder
    }

    /// 블록 인덱스를 페인트 순서(뒤→앞)로 정렬한다: 평면(behind<normal<front)
    /// → zOrder → 삽입순. 페인트·히트가 같은 순서를 쓰는 단일 지점이고, 블록
    /// 배열 자체는 문서 논리 순서로 남아 선택/복사 순서를 보존한다 (#8/#9/#10).
    public static func paintOrdered(
        _ blocks: [AnyHwpBlock]
    ) -> [(index: Int, block: AnyHwpBlock)] {
        blocks.enumerated().sorted { lhs, rhs in
            if lhs.element.paintPlane != rhs.element.paintPlane {
                return lhs.element.paintPlane < rhs.element.paintPlane
            }
            if lhs.element.zOrder != rhs.element.zOrder {
                return lhs.element.zOrder < rhs.element.zOrder
            }
            return lhs.offset < rhs.offset
        }.map { (index: $0.offset, block: $0.element) }
    }
}

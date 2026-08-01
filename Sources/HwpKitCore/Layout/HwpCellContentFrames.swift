import CoreGraphics
import CoreHwp
import Foundation

/// 셀 안에 재귀 레이아웃된 중첩 표.
public struct HwpNestedTableFrame: @unchecked Sendable, Hashable {
    /// 바깥 표-로컬 좌표계에서 중첩 표가 차지하는 영역
    public let rect: CGRect
    /// 중첩 표 자체 레이아웃 (origin 0,0 좌표계)
    public let table: HwpTableFrame
    /// 원본 컨트롤 참조 (편집 대비)
    public let controlInstanceId: UInt32
    /// 글 뒤로 배치 (표 70 textWrap) — 표도 그림·도형과 같은 페인트 평면을 갖는다
    /// (R47 #1). 이 값이 없으면 walker가 표를 무조건 마지막에 그려 글 뒤로 표가
    /// 텍스트 앞에 나온다.
    public let paintsBehindText: Bool
    /// 같은 평면 안 정렬 키 (zOrder → 원본 ctrlHeaderArray 순서)
    public let zOrder: Int32
    public let sourceOrder: Int
    /// 이 개체를 낸 `ctrlHeaderArray` 서수 (`HwpAttributedStringKey.controlIndex`
    /// 와 같은 값) — `%hlk`가 개체를 감쌌을 때 그 링크가 **이 개체의 것**인지
    /// 판별하는 열쇠다 (R50). 링크는 개체가 아니라 부모 문단의 U+FFFC run에
    /// 붙으므로, 지점 포함만으로 구제하면 옆의 다른 링크 텍스트까지 살아난다.
    public let controlIndex: Int
    /// 이 개체를 낸 문단의 `paraId` — `controlIndex` 는 문단마다 0부터 다시
    /// 시작하므로 (`ctrlHeaderArray.enumerated()`) 여러 문단을 가진 셀·글상자에서는
    /// 서수만으로 유일하지 않다. 감싼 링크의 열쇠는 **(문단, 서수) 쌍**이다 (R51 #1).
    public let paragraphId: UInt32
    /// 분할이 마커 문단을 반대 조각으로 보낸 뒤에도 살아남는 **감싼 링크 URL**
    /// (R58). `HwpTableSplitter.splitCell`이 조각을 만들기 **전에** 해석해 실어
    /// 보낸다 — 조각의 문단에는 U+FFFC run이 없어 (문단, 서수) 조회가 실패한다.
    public let wrapperURL: String?

    public init(
        rect: CGRect,
        table: HwpTableFrame,
        controlInstanceId: UInt32,
        paintsBehindText: Bool = false,
        zOrder: Int32 = 0,
        sourceOrder: Int = 0,
        controlIndex: Int = -1,
        paragraphId: UInt32 = 0,
        wrapperURL: String? = nil
    ) {
        self.rect = rect
        self.table = table
        self.controlInstanceId = controlInstanceId
        self.paintsBehindText = paintsBehindText
        self.zOrder = zOrder
        self.sourceOrder = sourceOrder
        self.controlIndex = controlIndex
        self.paragraphId = paragraphId
        self.wrapperURL = wrapperURL
    }

    /// rect만 바꾼 사본 — 세로 정렬·분할 이동 시 나머지 필드 누락을 막는다.
    /// 손으로 재구성하면 감싼 링크 열쇠와 평면·정렬 키가 기본값으로 떨어진다 (R52).
    /// 감싼 링크 URL만 바꾼 사본 — 분할 전 해석값을 개체에 고정한다 (R58)
    public func withWrapperURL(_ wrapperURL: String?) -> HwpNestedTableFrame {
        HwpNestedTableFrame(
            rect: rect,
            table: table,
            controlInstanceId: controlInstanceId,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }

    public func withRect(_ rect: CGRect) -> HwpNestedTableFrame {
        HwpNestedTableFrame(
            rect: rect,
            table: table,
            controlInstanceId: controlInstanceId,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }

    /// 안쪽 레이아웃만 바꾼 사본 (반복 제목 클론 표식)
    public func withTable(_ table: HwpTableFrame) -> HwpNestedTableFrame {
        HwpNestedTableFrame(
            rect: rect,
            table: table,
            controlInstanceId: controlInstanceId,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }
}

/// 셀 안 그림 (표-로컬 rect + BinItem 참조).
/// 한글은 셀 안 개체를 셀 콘텐츠로 배치한다 — 페이지 흐름 블록으로 방출하면
/// 큰 그림이 페이지를 밀어내 페이지 수가 한글과 어긋난다 (noori 실측 3쪽).
public struct HwpCellImage: Sendable, Hashable {
    /// 표-로컬 좌표계의 그림 영역
    public let rect: CGRect
    public let binItemId: UInt32
    public let style: HwpImageRenderStyle?
    /// 테두리 색 (없으면 테두리 없음)
    public let borderColor: HwpRGBColor?
    /// 테두리 두께 (pt)
    public let borderWidth: CGFloat
    /// 글 뒤로 (behindText) — 셀 텍스트보다 먼저 (아래에) 그린다 (R30 #2)
    public let paintsBehindText: Bool
    /// 겹치는 개체 z-순서 (표 70) — 같은 평면 안 페인트 정렬 기준
    public let zOrder: Int32
    /// 같은 zOrder의 이종 컨트롤 간 원본 (ctrlHeaderArray) 순서 — 동순위
    /// tiebreak이 종류-버킷 순서로 무너지지 않게 한다 (R31 #3)
    public let sourceOrder: Int
    /// 페이지 절단면에 걸친 그림의 가시 영역 (표-로컬, nil = 전체).
    /// rect는 저작 기하를 유지한다 — rect 축소는 스케일 왜곡 (R32 #2)
    public let clipRect: CGRect?
    /// 원본 컨트롤 참조 (편집 대비)
    public let controlInstanceId: UInt32
    /// 이 개체를 낸 `ctrlHeaderArray` 서수 (`HwpAttributedStringKey.controlIndex`
    /// 와 같은 값) — `%hlk`가 개체를 감쌌을 때 그 링크가 **이 개체의 것**인지
    /// 판별하는 열쇠다 (R50). 링크는 개체가 아니라 부모 문단의 U+FFFC run에
    /// 붙으므로, 지점 포함만으로 구제하면 옆의 다른 링크 텍스트까지 살아난다.
    public let controlIndex: Int
    /// 이 개체를 낸 문단의 `paraId` — `controlIndex` 는 문단마다 0부터 다시
    /// 시작하므로 (`ctrlHeaderArray.enumerated()`) 여러 문단을 가진 셀·글상자에서는
    /// 서수만으로 유일하지 않다. 감싼 링크의 열쇠는 **(문단, 서수) 쌍**이다 (R51 #1).
    public let paragraphId: UInt32
    /// 분할이 마커 문단을 반대 조각으로 보낸 뒤에도 살아남는 **감싼 링크 URL**
    /// (R58). `HwpTableSplitter.splitCell`이 조각을 만들기 **전에** 해석해 실어
    /// 보낸다 — 조각의 문단에는 U+FFFC run이 없어 (문단, 서수) 조회가 실패한다.
    public let wrapperURL: String?

    public init(
        rect: CGRect,
        binItemId: UInt32,
        style: HwpImageRenderStyle?,
        borderColor: HwpRGBColor? = nil,
        borderWidth: CGFloat = 0,
        paintsBehindText: Bool = false,
        zOrder: Int32 = 0,
        sourceOrder: Int = 0,
        clipRect: CGRect? = nil,
        controlInstanceId: UInt32,
        controlIndex: Int = -1,
        paragraphId: UInt32 = 0,
        wrapperURL: String? = nil
    ) {
        self.rect = rect
        self.binItemId = binItemId
        self.style = style
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.paintsBehindText = paintsBehindText
        self.zOrder = zOrder
        self.sourceOrder = sourceOrder
        self.clipRect = clipRect
        self.controlInstanceId = controlInstanceId
        self.controlIndex = controlIndex
        self.paragraphId = paragraphId
        self.wrapperURL = wrapperURL
    }

    /// **실제로 보이는 영역** — 페이지 절단면에 걸친 조각은 `clipRect` 안만 칠한다.
    ///
    /// 그리기는 저작 rect + CG 클립으로 한다 (rect를 줄이면 스케일 왜곡, R32 #2).
    /// 반면 **히트와 링크 방출은 이 교집합**을 봐야 잘려 나가 안 보이는 자리가
    /// 눌리거나 링크로 표시되지 않는다 (R57) — 두 소비자가 이 하나를 공유한다.
    public var visibleRect: CGRect {
        clipRect.map { rect.intersection($0) } ?? rect
    }

    /// rect만 바꾼 사본 — 분할/정렬 이동 시 나머지 필드 누락을 막는다.
    /// 감싼 링크 URL만 바꾼 사본 — 분할 전 해석값을 개체에 고정한다 (R58)
    public func withWrapperURL(_ wrapperURL: String?) -> HwpCellImage {
        HwpCellImage(
            rect: rect,
            binItemId: binItemId,
            style: style,
            borderColor: borderColor,
            borderWidth: borderWidth,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            clipRect: clipRect,
            controlInstanceId: controlInstanceId,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }

    public func withRect(_ rect: CGRect) -> HwpCellImage {
        HwpCellImage(
            rect: rect,
            binItemId: binItemId,
            style: style,
            borderColor: borderColor,
            borderWidth: borderWidth,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            clipRect: clipRect,
            controlInstanceId: controlInstanceId,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }

    /// 가시 영역만 바꾼 사본 (분할 조각 배정)
    public func withClip(_ clipRect: CGRect?) -> HwpCellImage {
        HwpCellImage(
            rect: rect,
            binItemId: binItemId,
            style: style,
            borderColor: borderColor,
            borderWidth: borderWidth,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            clipRect: clipRect,
            controlInstanceId: controlInstanceId,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }

    /// rect·clipRect를 함께 이동한 사본 — 분할 세그먼트 rebase에서 클립이
    /// 제자리에 남지 않게 한다 (R32 #2)
    public func offsetBy(deltaX: CGFloat, deltaY: CGFloat) -> HwpCellImage {
        withRect(rect.offsetBy(dx: deltaX, dy: deltaY))
            .withClip(clipRect?.offsetBy(dx: deltaX, dy: deltaY))
    }
}

/// 셀/글상자 안 도형 (컨테이너-로컬 rect + 지오메트리).
/// 한글은 컨테이너 안 개체를 컨테이너 콘텐츠로 배치한다 — 페이지 흐름
/// 블록으로 방출하면 컨테이너 밖 좌표에 그려진다 (R29 #1).
public struct HwpCellShape: @unchecked Sendable, Hashable {
    public let rect: CGRect
    public let geometry: HwpShapeGeometry
    /// 글 뒤로 (behindText) — 셀 텍스트보다 먼저 (아래에) 그린다 (R30 #2)
    public let paintsBehindText: Bool
    /// 겹치는 개체 z-순서 (표 70) — 같은 평면 안 페인트 정렬 기준
    public let zOrder: Int32
    /// 같은 zOrder의 이종 컨트롤 간 원본 순서 (R31 #3)
    public let sourceOrder: Int
    /// 원본 컨트롤 참조 (편집 대비)
    public let controlInstanceId: UInt32
    /// 이 개체를 낸 `ctrlHeaderArray` 서수 (`HwpAttributedStringKey.controlIndex`
    /// 와 같은 값) — `%hlk`가 개체를 감쌌을 때 그 링크가 **이 개체의 것**인지
    /// 판별하는 열쇠다 (R50). 링크는 개체가 아니라 부모 문단의 U+FFFC run에
    /// 붙으므로, 지점 포함만으로 구제하면 옆의 다른 링크 텍스트까지 살아난다.
    public let controlIndex: Int
    /// 이 개체를 낸 문단의 `paraId` — `controlIndex` 는 문단마다 0부터 다시
    /// 시작하므로 (`ctrlHeaderArray.enumerated()`) 여러 문단을 가진 셀·글상자에서는
    /// 서수만으로 유일하지 않다. 감싼 링크의 열쇠는 **(문단, 서수) 쌍**이다 (R51 #1).
    public let paragraphId: UInt32
    /// 분할이 마커 문단을 반대 조각으로 보낸 뒤에도 살아남는 **감싼 링크 URL**
    /// (R58). `HwpTableSplitter.splitCell`이 조각을 만들기 **전에** 해석해 실어
    /// 보낸다 — 조각의 문단에는 U+FFFC run이 없어 (문단, 서수) 조회가 실패한다.
    public let wrapperURL: String?

    public init(
        rect: CGRect,
        geometry: HwpShapeGeometry,
        paintsBehindText: Bool = false,
        zOrder: Int32 = 0,
        sourceOrder: Int = 0,
        controlInstanceId: UInt32,
        controlIndex: Int = -1,
        paragraphId: UInt32 = 0,
        wrapperURL: String? = nil
    ) {
        self.rect = rect
        self.geometry = geometry
        self.paintsBehindText = paintsBehindText
        self.zOrder = zOrder
        self.sourceOrder = sourceOrder
        self.controlInstanceId = controlInstanceId
        self.controlIndex = controlIndex
        self.paragraphId = paragraphId
        self.wrapperURL = wrapperURL
    }

    /// 감싼 링크 URL만 바꾼 사본 — 분할 전 해석값을 개체에 고정한다 (R58)
    public func withWrapperURL(_ wrapperURL: String?) -> HwpCellShape {
        HwpCellShape(
            rect: rect,
            geometry: geometry,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            controlInstanceId: controlInstanceId,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }

    public func withRect(_ rect: CGRect) -> HwpCellShape {
        HwpCellShape(
            rect: rect,
            geometry: geometry,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            controlInstanceId: controlInstanceId,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }
}

/// 셀 안 글상자 (표-로컬 rect + 글상자 레이아웃).
public struct HwpCellTextbox: @unchecked Sendable, Hashable {
    public let rect: CGRect
    /// 글상자 자체 레이아웃 (origin 0,0 좌표계)
    public let textbox: HwpTextboxFrame
    /// 글 뒤로 (behindText) — 셀 텍스트보다 먼저 (아래에) 그린다 (R30 #2)
    public let paintsBehindText: Bool
    /// 겹치는 개체 z-순서 (표 70) — 같은 평면 안 페인트 정렬 기준
    public let zOrder: Int32
    /// 같은 zOrder의 이종 컨트롤 간 원본 순서 (R31 #3)
    public let sourceOrder: Int
    /// 원본 컨트롤 참조 (편집 대비)
    public let controlInstanceId: UInt32
    /// 이 개체를 낸 `ctrlHeaderArray` 서수 (`HwpAttributedStringKey.controlIndex`
    /// 와 같은 값) — `%hlk`가 개체를 감쌌을 때 그 링크가 **이 개체의 것**인지
    /// 판별하는 열쇠다 (R50). 링크는 개체가 아니라 부모 문단의 U+FFFC run에
    /// 붙으므로, 지점 포함만으로 구제하면 옆의 다른 링크 텍스트까지 살아난다.
    public let controlIndex: Int
    /// 이 개체를 낸 문단의 `paraId` — `controlIndex` 는 문단마다 0부터 다시
    /// 시작하므로 (`ctrlHeaderArray.enumerated()`) 여러 문단을 가진 셀·글상자에서는
    /// 서수만으로 유일하지 않다. 감싼 링크의 열쇠는 **(문단, 서수) 쌍**이다 (R51 #1).
    public let paragraphId: UInt32
    /// 분할이 마커 문단을 반대 조각으로 보낸 뒤에도 살아남는 **감싼 링크 URL**
    /// (R58). `HwpTableSplitter.splitCell`이 조각을 만들기 **전에** 해석해 실어
    /// 보낸다 — 조각의 문단에는 U+FFFC run이 없어 (문단, 서수) 조회가 실패한다.
    public let wrapperURL: String?

    public init(
        rect: CGRect,
        textbox: HwpTextboxFrame,
        paintsBehindText: Bool = false,
        zOrder: Int32 = 0,
        sourceOrder: Int = 0,
        controlInstanceId: UInt32,
        controlIndex: Int = -1,
        paragraphId: UInt32 = 0,
        wrapperURL: String? = nil
    ) {
        self.rect = rect
        self.textbox = textbox
        self.paintsBehindText = paintsBehindText
        self.zOrder = zOrder
        self.sourceOrder = sourceOrder
        self.controlInstanceId = controlInstanceId
        self.controlIndex = controlIndex
        self.paragraphId = paragraphId
        self.wrapperURL = wrapperURL
    }

    /// 감싼 링크 URL만 바꾼 사본 — 분할 전 해석값을 개체에 고정한다 (R58)
    public func withWrapperURL(_ wrapperURL: String?) -> HwpCellTextbox {
        HwpCellTextbox(
            rect: rect,
            textbox: textbox,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            controlInstanceId: controlInstanceId,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }

    public func withRect(_ rect: CGRect) -> HwpCellTextbox {
        HwpCellTextbox(
            rect: rect,
            textbox: textbox,
            paintsBehindText: paintsBehindText,
            zOrder: zOrder,
            sourceOrder: sourceOrder,
            controlInstanceId: controlInstanceId,
            controlIndex: controlIndex,
            paragraphId: paragraphId,
            wrapperURL: wrapperURL
        )
    }
}

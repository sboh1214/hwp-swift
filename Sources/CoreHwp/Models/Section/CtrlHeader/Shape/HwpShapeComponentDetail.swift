import Foundation

/** 좌표 한 점 (개체 좌표계, HWPUNIT) */
public struct HwpShapePoint: HwpPrimitive {
    public var x: Int32
    public var y: Int32

    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }
}

/** scale/rotation matrix 한 쌍 (표 84). 각 행렬은 3×3에서 마지막 행 (0,0,1)을 생략한 double 6개다. */
public struct HwpShapeMatrixPair: HwpPrimitive {
    public var scale: [Double]
    public var rotation: [Double]

    public init(scale: [Double], rotation: [Double]) {
        self.scale = scale
        self.rotation = rotation
    }
}

/** 테두리 선 정보 (표 86; 실파일 13 byte) */
public struct HwpShapeBorderLine: HwpPrimitive {
    /** 선 색상 */
    public var color: HwpColor
    /** 선 굵기 (HWPUNIT; 실제 파일은 INT32로 기록 — 스펙 표 86의 INT16는 오기) */
    public var width: Int32
    /** 선 속성 bit field (표 87) */
    public var property: UInt32
    /** Outline style (표 88: 0 normal, 1 outer, 2 inner) */
    public var outlineStyle: UInt8

    public init(color: HwpColor, width: Int32, property: UInt32, outlineStyle: UInt8) {
        self.color = color
        self.width = width
        self.property = property
        self.outlineStyle = outlineStyle
    }

    /** 선 종류 (표 87 bits 0-5). 그리기 개체에서 0은 선 없음, 1이 실선으로 관측된다. */
    public var lineType: Int {
        Int(property & 0b111111)
    }

    /** 선이 그려지는 종류인지 (0 = 선 없음) */
    public var hasVisibleLine: Bool {
        lineType != 0
    }

    /// color(4) + width INT32(4) + property(4) + outline(1). 픽스처 바이트로 검증된 layout.
    static let byteCount = 13

    static func decode(from data: Data, at offset: Int) -> HwpShapeBorderLine? {
        guard data.count >= offset + byteCount else { return nil }
        do {
            return HwpShapeBorderLine(
                color: HwpColor(try data.readLittleEndianUInt32(at: offset)),
                width: try data.readLittleEndianInt32(at: offset + 4),
                property: try data.readLittleEndianUInt32(at: offset + 8),
                outlineStyle: try data.readUInt8(at: offset + 12)
            )
        } catch {
            return nil
        }
    }
}

/** 채우기 정보 (표 28). 단색 채우기만 필드로 해석하고 나머지는 raw로 보존한다. */
public struct HwpFillInfo: HwpPrimitive {
    /** 채우기 종류 flag (0x01 단색, 0x02 이미지, 0x04 그러데이션) */
    public var type: UInt32
    /** 단색 채우기일 때 배경색 */
    public var solidBackgroundColor: HwpColor?
    /** 단색 채우기일 때 무늬색 */
    public var solidPatternColor: HwpColor?
    /** 단색 채우기일 때 무늬 종류 (-1 = 무늬 없음) */
    public var solidPatternType: Int32?
    /** type flag 뒤의 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data

    public init(
        type: UInt32 = 0,
        solidBackgroundColor: HwpColor? = nil,
        solidPatternColor: HwpColor? = nil,
        solidPatternType: Int32? = nil,
        rawPayload: Data = Data()
    ) {
        self.type = type
        self.solidBackgroundColor = solidBackgroundColor
        self.solidPatternColor = solidPatternColor
        self.solidPatternType = solidPatternType
        self.rawPayload = rawPayload
    }

    public var hasSolidFill: Bool {
        type & 0x1 != 0
    }

    static func decode(from data: Data, at offset: Int) -> HwpFillInfo? {
        guard data.count >= offset + 4 else { return nil }
        do {
            let type = try data.readLittleEndianUInt32(at: offset)
            var fill = HwpFillInfo(type: type, rawPayload: Data(data.dropFirst(offset + 4)))
            if type & 0x1 != 0, data.count >= offset + 16 {
                fill.solidBackgroundColor = HwpColor(
                    try data.readLittleEndianUInt32(at: offset + 4)
                )
                fill.solidPatternColor = HwpColor(try data.readLittleEndianUInt32(at: offset + 8))
                fill.solidPatternType = try data.readLittleEndianInt32(at: offset + 12)
            }
            return fill
        } catch {
            return nil
        }
    }
}

/**
 개체 요소 속성 (표 83) + 렌더링 행렬 (표 84) + 테두리 선 (표 86) + 채우기 (표 28)

 SHAPE_COMPONENT record payload의 ctrl id 뒤에 이어지는 그리기 개체 공통 속성이다.
 GenShapeObject 소유 요소는 ctrl id가 두 번 기록되므로 (표 82) 앞 8 byte를 건너뛴다.
 */
public struct HwpShapeComponentDetail: HwpPrimitive {
    /** 그룹 내에서의 X 오프셋 (개체 좌표계) */
    public var groupOffsetX: Int32
    /** 그룹 내에서의 Y 오프셋 */
    public var groupOffsetY: Int32
    /** 몇 번이나 그룹 되었는지 */
    public var groupCount: UInt16
    /** local file version */
    public var localFileVersion: UInt16
    /** 개체 생성 시 초기 폭 (HWPUNIT) */
    public var initialWidth: UInt32
    /** 개체 생성 시 초기 높이 */
    public var initialHeight: UInt32
    /** 현재 폭 */
    public var currentWidth: UInt32
    /** 현재 높이 */
    public var currentHeight: UInt32
    /** 속성 bit 0: 가로로 뒤집힘 */
    public var isHorizontallyFlipped: Bool
    /** 속성 bit 1: 세로로 뒤집힘 */
    public var isVerticallyFlipped: Bool
    /** 회전각 (도 단위 관례) */
    public var rotationAngle: Int16
    /** 회전 중심 x (개체 좌표계) */
    public var rotationCenterX: Int32
    /** 회전 중심 y */
    public var rotationCenterY: Int32
    /** translation matrix (double 6개: m0 m1 m2 / m3 m4 m5, 마지막 행 0 0 1 생략) */
    public var translationMatrix: [Double]
    /** scale/rotation matrix 쌍 (그룹 횟수만큼) */
    public var scaleRotationMatrixPairs: [HwpShapeMatrixPair]
    /** 테두리 선 정보. 행렬 뒤 payload가 부족하면 nil. */
    public var borderLine: HwpShapeBorderLine?
    /** 채우기 정보. payload가 부족하면 nil. */
    public var fill: HwpFillInfo?

    static let elementByteCount = 42

    /// SHAPE_COMPONENT payload에서 best-effort로 디코딩한다.
    /// - Parameter payload: record 전체 payload (ctrl id 포함)
    static func decode(from payload: Data) -> HwpShapeComponentDetail? {
        let offset = elementOffset(in: payload)
        guard payload.count >= offset + elementByteCount else { return nil }

        do {
            let flip = try payload.readLittleEndianUInt32(at: offset + 28)
            var detail = HwpShapeComponentDetail(
                groupOffsetX: try payload.readLittleEndianInt32(at: offset),
                groupOffsetY: try payload.readLittleEndianInt32(at: offset + 4),
                groupCount: try payload.readLittleEndianUInt16(at: offset + 8),
                localFileVersion: try payload.readLittleEndianUInt16(at: offset + 10),
                initialWidth: try payload.readLittleEndianUInt32(at: offset + 12),
                initialHeight: try payload.readLittleEndianUInt32(at: offset + 16),
                currentWidth: try payload.readLittleEndianUInt32(at: offset + 20),
                currentHeight: try payload.readLittleEndianUInt32(at: offset + 24),
                isHorizontallyFlipped: flip & 0x1 != 0,
                isVerticallyFlipped: flip & 0x2 != 0,
                rotationAngle: try payload.readLittleEndianInt16(at: offset + 32),
                rotationCenterX: try payload.readLittleEndianInt32(at: offset + 34),
                rotationCenterY: try payload.readLittleEndianInt32(at: offset + 38),
                translationMatrix: [],
                scaleRotationMatrixPairs: []
            )

            var cursor = offset + elementByteCount
            guard payload.count >= cursor + 2 else { return detail }
            let matrixPairCount = Int(try payload.readLittleEndianUInt16(at: cursor))
            cursor += 2

            guard let translation = Self.matrix(from: payload, at: cursor) else { return detail }
            detail.translationMatrix = translation
            cursor += 48

            var pairs: [HwpShapeMatrixPair] = []
            for _ in 0 ..< matrixPairCount {
                guard let scale = Self.matrix(from: payload, at: cursor),
                      let rotation = Self.matrix(from: payload, at: cursor + 48)
                else { break }
                pairs.append(HwpShapeMatrixPair(scale: scale, rotation: rotation))
                cursor += 96
            }
            detail.scaleRotationMatrixPairs = pairs
            // 선언된 행렬 쌍을 다 읽지 못했으면 (truncated payload) 남은 바이트를
            // 테두리/채우기로 오독하지 않는다.
            guard pairs.count == matrixPairCount else { return detail }

            detail.borderLine = HwpShapeBorderLine.decode(from: payload, at: cursor)
            if detail.borderLine != nil {
                cursor += HwpShapeBorderLine.byteCount
                detail.fill = HwpFillInfo.decode(from: payload, at: cursor)
            }
            return detail
        } catch {
            return nil
        }
    }

    init(
        groupOffsetX: Int32,
        groupOffsetY: Int32,
        groupCount: UInt16,
        localFileVersion: UInt16,
        initialWidth: UInt32,
        initialHeight: UInt32,
        currentWidth: UInt32,
        currentHeight: UInt32,
        isHorizontallyFlipped: Bool,
        isVerticallyFlipped: Bool,
        rotationAngle: Int16,
        rotationCenterX: Int32,
        rotationCenterY: Int32,
        translationMatrix: [Double],
        scaleRotationMatrixPairs: [HwpShapeMatrixPair],
        borderLine: HwpShapeBorderLine? = nil,
        fill: HwpFillInfo? = nil
    ) {
        self.groupOffsetX = groupOffsetX
        self.groupOffsetY = groupOffsetY
        self.groupCount = groupCount
        self.localFileVersion = localFileVersion
        self.initialWidth = initialWidth
        self.initialHeight = initialHeight
        self.currentWidth = currentWidth
        self.currentHeight = currentHeight
        self.isHorizontallyFlipped = isHorizontallyFlipped
        self.isVerticallyFlipped = isVerticallyFlipped
        self.rotationAngle = rotationAngle
        self.rotationCenterX = rotationCenterX
        self.rotationCenterY = rotationCenterY
        self.translationMatrix = translationMatrix
        self.scaleRotationMatrixPairs = scaleRotationMatrixPairs
        self.borderLine = borderLine
        self.fill = fill
    }

    /// ctrl id가 두 번 기록되는 경우 (gso 소유 요소) 8 byte, 아니면 4 byte를 건너뛴다.
    private static func elementOffset(in payload: Data) -> Int {
        if payload.count >= 8,
           let first = readOptionalUInt32(from: payload, at: 0),
           let second = readOptionalUInt32(from: payload, at: 4),
           first == second
        {
            return 8
        }
        return MemoryLayout<UInt32>.size
    }

    private static func matrix(from data: Data, at offset: Int) -> [Double]? {
        guard data.count >= offset + 48 else { return nil }
        do {
            return try (0 ..< 6).map { try data.readLittleEndianDouble(at: offset + $0 * 8) }
        } catch {
            return nil
        }
    }

    private static func readOptionalUInt32(from data: Data, at offset: Int) -> UInt32? {
        do {
            return try data.readLittleEndianUInt32(at: offset)
        } catch {
            return nil
        }
    }
}

// MARK: - 개체 요소 세부 디코딩 (표 92-103)

/** 선 개체 세부 (표 92, 18 byte) */
public struct HwpShapeLineDetail: HwpPrimitive {
    public var start: HwpShapePoint
    public var end: HwpShapePoint
    /** 처음 생성 시 수직/수평선 방향 플래그 */
    public var attribute: UInt16?

    public init(start: HwpShapePoint, end: HwpShapePoint, attribute: UInt16? = nil) {
        self.start = start
        self.end = end
        self.attribute = attribute
    }

    static func decode(from data: Data) -> HwpShapeLineDetail? {
        guard data.count >= 16 else { return nil }
        do {
            return HwpShapeLineDetail(
                start: HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 0),
                    y: try data.readLittleEndianInt32(at: 4)
                ),
                end: HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 8),
                    y: try data.readLittleEndianInt32(at: 12)
                ),
                attribute: data.count >= 18 ? try data.readLittleEndianUInt16(at: 16) : nil
            )
        } catch {
            return nil
        }
    }
}

/** 사각형 개체 세부 (표 94, 33 byte) */
public struct HwpShapeRectangleDetail: HwpPrimitive {
    /** 모서리 곡률 % (0 직각, 20 둥근, 50 반원) */
    public var cornerRoundness: UInt8
    /** 4개 꼭짓점 좌표 */
    public var corners: [HwpShapePoint]

    public init(cornerRoundness: UInt8, corners: [HwpShapePoint]) {
        self.cornerRoundness = cornerRoundness
        self.corners = corners
    }

    static func decode(from data: Data) -> HwpShapeRectangleDetail? {
        guard data.count >= 33 else { return nil }
        do {
            let roundness = try data.readUInt8(at: 0)
            let corners = try (0 ..< 4).map { index in
                HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 1 + index * 8),
                    y: try data.readLittleEndianInt32(at: 5 + index * 8)
                )
            }
            return HwpShapeRectangleDetail(cornerRoundness: roundness, corners: corners)
        } catch {
            return nil
        }
    }
}

/** 타원 개체 세부 (표 96, 60 byte) */
public struct HwpShapeEllipseDetail: HwpPrimitive {
    /** 속성 (표 97: bit1 호로 바뀌었는지, bits 2-9 호의 종류) */
    public var property: UInt32
    public var center: HwpShapePoint
    public var firstAxis: HwpShapePoint
    public var secondAxis: HwpShapePoint
    /** 호로 바뀐 경우의 호 시작점 (표 96 offset 28, 60 byte 타원에만 존재) */
    public var arcStart: HwpShapePoint?
    /** 호로 바뀐 경우의 호 끝점 (표 96 offset 36) */
    public var arcEnd: HwpShapePoint?

    public init(
        property: UInt32,
        center: HwpShapePoint,
        firstAxis: HwpShapePoint,
        secondAxis: HwpShapePoint,
        arcStart: HwpShapePoint? = nil,
        arcEnd: HwpShapePoint? = nil
    ) {
        self.property = property
        self.center = center
        self.firstAxis = firstAxis
        self.secondAxis = secondAxis
        self.arcStart = arcStart
        self.arcEnd = arcEnd
    }

    public var isArc: Bool {
        property & 0x2 != 0
    }

    /// 호로 바뀐 경우의 닫힘 종류 (표 97 bits 2-9). 알 수 없는 값은 open으로 폴백.
    public var arcKind: HwpShapeArcKind {
        HwpShapeArcKind(rawValue: (property >> 2) & 0xFF) ?? .open
    }

    static func decode(from data: Data) -> HwpShapeEllipseDetail? {
        guard data.count >= 28 else { return nil }
        do {
            // 60 byte 타원은 축 뒤에 호 시작/끝점 쌍을 더 갖는다 (표 96 offset 28~59:
            // start1/end1/start2/end2). 호 변환(bit1) 렌더에 필요한 start1/end1만
            // typed view로 노출하고 나머지는 rawPayload에 보존한다 (R45 #2).
            let arcStart = data.count >= 36
                ? HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 28),
                    y: try data.readLittleEndianInt32(at: 32)
                )
                : nil
            let arcEnd = data.count >= 44
                ? HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 36),
                    y: try data.readLittleEndianInt32(at: 40)
                )
                : nil
            return HwpShapeEllipseDetail(
                property: try data.readLittleEndianUInt32(at: 0),
                center: HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 4),
                    y: try data.readLittleEndianInt32(at: 8)
                ),
                firstAxis: HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 12),
                    y: try data.readLittleEndianInt32(at: 16)
                ),
                secondAxis: HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 20),
                    y: try data.readLittleEndianInt32(at: 24)
                ),
                arcStart: arcStart,
                arcEnd: arcEnd
            )
        } catch {
            return nil
        }
    }
}

/// 호로 바뀐 타원의 닫힘 종류 (표 97 bits 2-9). hwp-rs `ArcKind`(Normal/Pie/Chord)·
/// hwplib `ArcType`(Arc/CircularSector/Bow) 실측 매핑.
public enum HwpShapeArcKind: UInt32, Hashable, Sendable {
    /// 호 — 닫지 않는 열린 호
    case open = 0
    /// 부채꼴 — 중심으로 두 반지름을 그어 닫음
    case pie = 1
    /// 활 — 양 끝점을 직선(현)으로 이어 닫음
    case chord = 2
}

/** 호 개체 세부 (표 101, 28 byte) — 타원과 동일 필드 구성 */
public typealias HwpShapeArcDetail = HwpShapeEllipseDetail

/** 다각형 개체 세부 (표 99) */
public struct HwpShapePolygonDetail: HwpPrimitive {
    public var points: [HwpShapePoint]

    public init(points: [HwpShapePoint]) {
        self.points = points
    }

    static func decode(from data: Data) -> HwpShapePolygonDetail? {
        guard data.count >= 2 else { return nil }
        do {
            let count = Int(try data.readLittleEndianInt16(at: 0))
            guard count > 0, data.count >= 2 + count * 8 else { return nil }
            let points = try (0 ..< count).map { index in
                HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 2 + index * 8),
                    y: try data.readLittleEndianInt32(at: 6 + index * 8)
                )
            }
            return HwpShapePolygonDetail(points: points)
        } catch {
            return nil
        }
    }
}

/** 곡선 개체 세부 (표 103) */
public struct HwpShapeCurveDetail: HwpPrimitive {
    public var points: [HwpShapePoint]
    /** 구간 종류 (0 = line, 1 = curve). points.count - 1개. */
    public var segmentTypes: [UInt8]

    public init(points: [HwpShapePoint], segmentTypes: [UInt8]) {
        self.points = points
        self.segmentTypes = segmentTypes
    }

    static func decode(from data: Data) -> HwpShapeCurveDetail? {
        guard data.count >= 2 else { return nil }
        do {
            let count = Int(try data.readLittleEndianInt16(at: 0))
            guard count > 0, data.count >= 2 + count * 8 + max(0, count - 1) else { return nil }
            let points = try (0 ..< count).map { index in
                HwpShapePoint(
                    x: try data.readLittleEndianInt32(at: 2 + index * 8),
                    y: try data.readLittleEndianInt32(at: 6 + index * 8)
                )
            }
            let segmentTypes = try (0 ..< max(0, count - 1)).map { index in
                try data.readUInt8(at: 2 + count * 8 + index)
            }
            return HwpShapeCurveDetail(points: points, segmentTypes: segmentTypes)
        } catch {
            return nil
        }
    }
}

// MARK: - raw record에 세부 디코딩 접근자 연결

public extension HwpShapeComponent {
    /** 개체 요소 공통 속성 (표 83 + 행렬 + 테두리 선 + 채우기). payload가 짧으면 nil. */
    var detail: HwpShapeComponentDetail? {
        HwpShapeComponentDetail.decode(from: rawPayload)
    }
}

public extension HwpShapeComponentLine {
    var lineDetail: HwpShapeLineDetail? {
        HwpShapeLineDetail.decode(from: rawPayload)
    }
}

public extension HwpShapeComponentRectangle {
    var rectangleDetail: HwpShapeRectangleDetail? {
        HwpShapeRectangleDetail.decode(from: rawPayload)
    }
}

public extension HwpShapeComponentEllipse {
    var ellipseDetail: HwpShapeEllipseDetail? {
        HwpShapeEllipseDetail.decode(from: rawPayload)
    }
}

public extension HwpShapeComponentArc {
    /** 호는 속성 + 중심/축 좌표만 갖는다 (표 101). */
    var arcDetail: HwpShapeArcDetail? {
        HwpShapeArcDetail.decode(from: rawPayload)
    }
}

public extension HwpShapeComponentPolygon {
    var polygonDetail: HwpShapePolygonDetail? {
        HwpShapePolygonDetail.decode(from: rawPayload)
    }
}

public extension HwpShapeComponentCurve {
    var curveDetail: HwpShapeCurveDetail? {
        HwpShapeCurveDetail.decode(from: rawPayload)
    }
}

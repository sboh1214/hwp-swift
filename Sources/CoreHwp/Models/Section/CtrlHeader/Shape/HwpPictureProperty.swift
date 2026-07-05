import Foundation

/**
 그림 개체 속성 (표 107)

 SHAPE_COMPONENT_PICTURE record payload의 고정 prefix (71 byte) + BinItem id + 가변 tail.
 좌표는 개체 좌표계 HWPUNIT이다.
 */
public struct HwpPictureProperty: HwpPrimitive {
    /** 테두리 색 */
    public var borderColor: HwpColor
    /** 테두리 두께 (단위 미명세; 관례상 HWPUNIT 계열) */
    public var borderThickness: Int32
    /** 테두리 속성 bit field (표 87) */
    public var borderProperty: UInt32
    /** 이미지 테두리 사각형 4개 꼭짓점 (최초 삽입 시 크기) */
    public var imageCorners: [HwpShapePoint]
    /** 자르기 후 왼쪽 */
    public var cropLeft: Int32
    /** 자르기 후 위쪽 */
    public var cropTop: Int32
    /** 자르기 후 오른쪽 */
    public var cropRight: Int32
    /** 자르기 후 아래쪽 */
    public var cropBottom: Int32
    /** 안쪽 여백 (왼쪽/오른쪽/위쪽/아래쪽, HWPUNIT16) */
    public var innerMarginArray: [HWPUNIT16]
    /** 그림 밝기 */
    public var brightness: Int8
    /** 그림 명암 */
    public var contrast: Int8
    /** 그림 효과 (0 REAL_PIC, 1 GRAY_SCALE, 2 BLACK_WHITE, 4 PATTERN8x8) */
    public var effect: UInt8
    /** BinItem 아이디 (DocInfo HWPTAG_BIN_DATA 참조, 1-based) */
    public var binItemId: UInt16

    static func decode(from payload: Data) -> HwpPictureProperty? {
        guard payload.count >= 73 else { return nil }
        do {
            // 꼭짓점은 (x, y) interleaved 쌍으로 기록된다 (픽스처 바이트 검증).
            let corners = try (0 ..< 4).map { index in
                HwpShapePoint(
                    x: try payload.readLittleEndianInt32(at: 12 + index * 8),
                    y: try payload.readLittleEndianInt32(at: 16 + index * 8)
                )
            }
            return HwpPictureProperty(
                borderColor: HwpColor(try payload.readLittleEndianUInt32(at: 0)),
                borderThickness: try payload.readLittleEndianInt32(at: 4),
                borderProperty: try payload.readLittleEndianUInt32(at: 8),
                imageCorners: corners,
                cropLeft: try payload.readLittleEndianInt32(at: 44),
                cropTop: try payload.readLittleEndianInt32(at: 48),
                cropRight: try payload.readLittleEndianInt32(at: 52),
                cropBottom: try payload.readLittleEndianInt32(at: 56),
                innerMarginArray: try (0 ..< 4).map {
                    try payload.readLittleEndianInt16(at: 60 + $0 * 2)
                },
                brightness: Int8(bitPattern: try payload.readUInt8(at: 68)),
                contrast: Int8(bitPattern: try payload.readUInt8(at: 69)),
                effect: try payload.readUInt8(at: 70),
                binItemId: try payload.readLittleEndianUInt16(at: 71)
            )
        } catch {
            return nil
        }
    }

    public init(
        borderColor: HwpColor,
        borderThickness: Int32,
        borderProperty: UInt32,
        imageCorners: [HwpShapePoint],
        cropLeft: Int32,
        cropTop: Int32,
        cropRight: Int32,
        cropBottom: Int32,
        innerMarginArray: [HWPUNIT16],
        brightness: Int8,
        contrast: Int8,
        effect: UInt8,
        binItemId: UInt16
    ) {
        self.borderColor = borderColor
        self.borderThickness = borderThickness
        self.borderProperty = borderProperty
        self.imageCorners = imageCorners
        self.cropLeft = cropLeft
        self.cropTop = cropTop
        self.cropRight = cropRight
        self.cropBottom = cropBottom
        self.innerMarginArray = innerMarginArray
        self.brightness = brightness
        self.contrast = contrast
        self.effect = effect
        self.binItemId = binItemId
    }
}

public extension HwpShapeComponentPicture {
    /** 그림 개체 속성 (표 107). payload가 짧으면 nil. */
    var pictureProperty: HwpPictureProperty? {
        HwpPictureProperty.decode(from: rawPayload)
    }
}

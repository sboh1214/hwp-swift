import Foundation

/// `hp:pic`을 `.picture(HwpShapeControl)`로 옮긴다.
///
/// 하류(`HwpParagraphObjectCollector`·`HwpPaginator`)는 그림 속성을
/// `HwpShapeComponentPicture.rawPayload`의 표 107 바이트에서 **다시 디코드**
/// 하므로 (`pictureProperty`가 computed) 73바이트 payload를 여기서 합성한다.
/// `binItemId` 자리(offset 71)에는 manifest id → BinItem id 리맵 값을 실어
/// `HwpImageStore` 조인이 닫히게 한다.
enum HwpxPictureMapper {
    static func map(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) -> HwpShapeControl {
        let common = HwpxObjectCommonMapper.map(node, ctrlId: .picture)
        // img만 core vocabulary다 — 실측: BinData·noori 실저장본이 hc:img를
        // 쓴다 (sz·pos·outMargin·inMargin·imgRect·imgClip은 전부 hp).
        let image = node.childElements.first { $0.isNamed("img", in: HwpxNamespace.core) }
        let binItemId = image?.attribute("binaryItemIDRef")
            .flatMap { context.binItemIdByManifestId[$0] } ?? 0

        let payload = Self.pictureBytes(
            node, image: image, common: common, binItemId: binItemId
        )
        // flip·rotationInfo·renderingInfo·effects 등 미소비 자식은 렌더에
        // 반영되지 않으므로 진단으로 강등한다 — 부착처는 diagnostics walker가
        // 걷는 shapeControl.unknownChildren이다.
        let paragraphConsumed = ["sz", "pos", "outMargin", "imgRect", "imgClip", "inMargin"]
        var unknownChildren = node.childElements
            .filter { child in
                !paragraphConsumed.contains {
                    child.isNamed($0, in: HwpxNamespace.paragraph)
                } && !child.isNamed("img", in: HwpxNamespace.core)
            }
            .map { $0.syntheticUnknownRecord() }
        // 래퍼는 속성·pt 좌표만 읽는다 — 안의 미지 자식은 여기서 강등해야
        // 진단에 남는다 (paraPr 래퍼 강등과 같은 채널).
        if let image {
            unknownChildren += image.unconsumedChildRecords(consumed: [])
        }
        if let imgRect = node.paragraphFirstChild(named: "imgRect") {
            unknownChildren += imgRect.unconsumedChildRecords(
                consumed: ["pt0", "pt1", "pt2", "pt3"], in: HwpxNamespace.core
            )
            for ptName in ["pt0", "pt1", "pt2", "pt3"] {
                if let point = imgRect.childElements.first(where: {
                    $0.isNamed(ptName, in: HwpxNamespace.core)
                }) {
                    unknownChildren += point.unconsumedChildRecords(consumed: [])
                }
            }
        }
        if let imgClip = node.paragraphFirstChild(named: "imgClip") {
            unknownChildren += imgClip.unconsumedChildRecords(consumed: [])
        }
        // sz·pos·outMargin·inMargin은 속성만 읽는 잎 래퍼다 — 자식이 전부
        // 미소비라 여기서 강등해야 진단에 남는다.
        for wrapperName in ["sz", "pos", "outMargin", "inMargin"] {
            if let wrapper = node.paragraphFirstChild(named: wrapperName) {
                unknownChildren += wrapper.unconsumedChildRecords(consumed: [])
            }
        }
        let picture = HwpShapeComponentPicture(
            rawPayload: payload,
            binaryDataId: binItemId,
            rawTrailing: nil,
            unknownChildren: []
        )
        let component = HwpShapeComponent(
            rawCtrlId: HwpCommonCtrlId.picture.rawValue,
            ctrlId: .picture,
            ctrlIdName: "picture",
            rawPayload: Data(),
            rawTrailing: nil,
            pictureArray: [picture],
            oleArray: [],
            oleRecords: [],
            ctrlDataRecords: [],
            unknownChildren: []
        )
        return HwpShapeControl(
            ctrlId: .picture,
            commonCtrlProperty: common,
            rawPayload: Data(),
            rawTrailing: Data(),
            shapeComponentArray: [component],
            eqEditArray: [],
            eqEditRecords: [],
            ctrlDataRecords: [],
            unknownChildren: unknownChildren
        )
    }

    /// 표 107 고정 prefix 71바이트 + BinItem id 2바이트 합성.
    static func pictureBytes(
        _ node: HwpxXMLNode,
        image: HwpxXMLNode?,
        common: HwpCommonCtrlProperty,
        binItemId: UInt16
    ) -> Data {
        var payload = Data(capacity: 73)
        payload.appendHwpxLittleEndian(UInt32(0)) // 테두리 색
        payload.appendHwpxLittleEndian(UInt32(0)) // 테두리 두께 (0 = 없음)
        payload.appendHwpxLittleEndian(UInt32(0)) // 테두리 속성

        // 꼭짓점 4개 (x, y interleaved) — hp:imgRect의 hc:pt0..pt3, 없으면
        // 개체 크기의 직사각형으로 합성한다.
        let corners = Self.corners(node, common: common)
        for corner in corners {
            payload.appendHwpxLittleEndian(UInt32(bitPattern: corner.x))
            payload.appendHwpxLittleEndian(UInt32(bitPattern: corner.y))
        }

        let clip = node.paragraphFirstChild(named: "imgClip")
        for name in ["left", "top", "right", "bottom"] {
            payload.appendHwpxLittleEndian(
                UInt32(bitPattern: clip?.int32Attribute(name, default: 0) ?? 0)
            )
        }

        let margin = node.paragraphFirstChild(named: "inMargin")
        for name in ["left", "right", "top", "bottom"] {
            let value = Int16(clamping: margin?.intAttribute(name, default: 0) ?? 0)
            payload.append(UInt8(UInt16(bitPattern: value) & 0xFF))
            payload.append(UInt8(UInt16(bitPattern: value) >> 8))
        }

        payload.append(UInt8(bitPattern: Int8(
            clamping: image?.intAttribute("bright", default: 0) ?? 0
        )))
        payload.append(UInt8(bitPattern: Int8(
            clamping: image?.intAttribute("contrast", default: 0) ?? 0
        )))
        payload.append(Self.effects[image?.attribute("effect") ?? "REAL_PIC"] ?? 0)
        payload.append(UInt8(binItemId & 0xFF))
        payload.append(UInt8(binItemId >> 8))
        return payload
    }

    static func corners(
        _ node: HwpxXMLNode,
        common: HwpCommonCtrlProperty
    ) -> [(x: Int32, y: Int32)] {
        if let rect = node.paragraphFirstChild(named: "imgRect") {
            // pt는 core vocabulary다 (실측 hc:pt0-3) — 전역 매칭이면
            // hh:pt0 디코이가 좌표를 대체한다.
            let points = ["pt0", "pt1", "pt2", "pt3"].compactMap { ptName in
                rect.childElements.first { $0.isNamed(ptName, in: HwpxNamespace.core) }
            }
            if points.count == 4 {
                return points.map {
                    (x: $0.int32Attribute("x", default: 0),
                     y: $0.int32Attribute("y", default: 0))
                }
            }
        }
        let width = Int32(clamping: common.width)
        let height = Int32(clamping: common.height)
        return [(0, 0), (width, 0), (width, height), (0, height)]
    }

    static let effects: [String: UInt8] = [
        "REAL_PIC": 0, "GRAY_SCALE": 1, "BLACK_WHITE": 2, "PATTERN8x8": 4,
    ]
}

extension Data {
    /// 프로덕션 쪽 LE 기록 헬퍼 — 테스트 전용 ZipBuilder의 것과 별개다.
    mutating func appendHwpxLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

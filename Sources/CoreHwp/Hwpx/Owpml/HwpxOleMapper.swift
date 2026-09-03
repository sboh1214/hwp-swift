import Foundation

/// `hp:ole`을 `.ole(HwpShapeControl)`로 옮긴다 — `hp:pic` → `.picture`와 같은
/// 꼴이고, 개체 앵커(제어 문자 코드 11) 중 표·그림 다음의 typed 승격이다 (#134).
///
/// 렌더는 `HwpShapeComponentOLE.binaryDataId`만 읽는다 — `HwpPaginator.chartFrame`이
/// 그 id로 `HwpImageStore`의 BinData payload(4바이트 길이 프리픽스 + CFB)를 꺼내
/// `HwpEmbeddedChart` → `HwpChartParser` → `HwpChartPainter`로 내장 차트를 근사
/// 렌더한다. BinData 쪽은 `HwpxBinDataMapper`가 manifest 순서로 이미 열어 둔다
/// (`.ole` 항목도 `BIN%04X.ole` 스트림으로 등록) — 여기서는 `binaryItemIDRef`를
/// BinItem id로 리맵해 그 조인을 닫는다. 조판 경로는 무변경이다: `.ole`은
/// `.genShapeObject`와 같은 개체 분기를 이미 탄다.
///
/// 표 118 payload는 렌더 필수가 아니지만 바이너리 파싱 결과와 같은 모양으로 합성해
/// 붙인다. 게이트는 걸지 않는다 — 바이너리 `HwpShapeComponentOLE`는 payload를
/// `decoupledPayload`(양 모드 보존)로 읽으므로 `.viewer`에서도 남는 것이 패리티다
/// (`HwpxPictureMapper`의 73바이트와 같은 부류이고, `preservedPayload`로 비우는
/// `HwpxPageNumberMapper`와 다르다). 실물 레이아웃은 스펙 표 118과 달리 속성이
/// UINT32라 BinData ID가 offset 12다 (`HwpShapeComponentOLE` 주석). 합성은 문서화된
/// 필드까지 26바이트다 — 한글.app 저장본(chart 픽스처)은 뒤에 미해석 4바이트(0)가 더
/// 있으나 뜻을 모르는 바이트는 만들지 않는다. 테두리 3필드는 그림 매퍼와 같이 0으로
/// 두고 `hp:lineShape`는 소비하지 않는다(진단으로 강등 — 렌더가 읽지 않는다).
///
/// `<hp:switch>`의 2016 ooxmlchart 분기(`hp:chart chartIDRef`)는 파서가 버리고
/// `hp:default`의 `hp:ole`을 채택하므로(`HwpxNamespace.supportedSwitchNamespaces`)
/// 이 매퍼는 `hp:ole`만 본다. fallback 없이 `hp:chart`만 오는 문서는 종전대로
/// 같은 4CC(`$ole`)의 강등 앵커다 (`HwpxControlMapper.objectFourCCs`).
///
/// 실측 근거 (`Sources/CoreHwp/Hwpx/AGENTS.md` "OLE 개체"): chart 변환 쌍 —
/// `objectType="UNKNOWN"`·`drawAspect="CONTENT"`·`hasMoniker="0"`·`eqBaseLine="0"`·
/// `hc:extent 7200×7200`·`binaryItemIDRef="ole1"` ↔ HWP 쌍 payload
/// `01 00 00 00 | 20 1C 00 00 | 20 1C 00 00 | 01 00`. 나머지 열거 값은 미실측이고
/// 이름은 한컴 공개 OWPML 모델(`OWPML/Class/enumdef.h`)의 직렬화 표, 값은 표 119다.
enum HwpxOleMapper {
    /// 개체 앵커(제어 문자 코드 11) + typed 컨트롤 — `classify`의 분기.
    static func anchor(
        _ node: HwpxXMLNode, context: HwpxMappingContext
    ) -> HwpxRunChildAction {
        .anchor(
            code: 11,
            fourCC: HwpCommonCtrlId.ole.rawValue,
            ctrl: .ole(map(node, context: context))
        )
    }

    static func map(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) -> HwpShapeControl {
        let common = HwpxObjectCommonMapper.map(node, ctrlId: .ole)
        // manifest에 없는 참조는 0 — 스트림 없음으로 떨어져 차트 대신 도형 상자
        // 경로로 폴백한다 (그림의 댕글링 처리와 같다).
        let binItemId = node.attribute("binaryItemIDRef")
            .flatMap { context.binItemIdByManifestId[$0] } ?? 0
        let payload = Self.oleBytes(node, common: common, binItemId: binItemId)

        let element = HwpShapeComponentOLE(
            rawPayload: payload,
            binaryDataId: UInt32(binItemId),
            // 바이너리와 같은 절단 — 속성 UINT32 뒤가 rawTrailing이다.
            rawTrailing: Data(payload.dropFirst(4)),
            unknownChildren: []
        )
        let component = HwpShapeComponent(
            rawCtrlId: HwpCommonCtrlId.ole.rawValue,
            ctrlId: .ole,
            ctrlIdName: "ole",
            rawPayload: Data(),
            rawTrailing: nil,
            pictureArray: [],
            oleArray: [element],
            // 바이너리의 oleRecords는 같은 레코드의 raw 사본이다 — XML에는 원본
            // 레코드가 없으므로 비운다 (진단 walker는 oleArray만 걷는다).
            oleRecords: [],
            ctrlDataRecords: [],
            unknownChildren: []
        )
        return HwpShapeControl(
            ctrlId: .ole,
            commonCtrlProperty: common,
            rawPayload: Data(),
            rawTrailing: Data(),
            shapeComponentArray: [component],
            eqEditArray: [],
            eqEditRecords: [],
            ctrlDataRecords: [],
            unknownChildren: Self.unconsumedChildren(of: node, context: context)
        )
    }

    /// 미소비 자식의 진단 강등 — 부착처는 diagnostics walker가 걷는
    /// shapeControl.unknownChildren이다.
    static func unconsumedChildren(
        of node: HwpxXMLNode,
        context: HwpxMappingContext
    ) -> [HwpUnknownRecord] {
        // extent만 core vocabulary다 (실측 hc:extent) — sz·pos·outMargin은 hp.
        let consumed = [
            "sz": HwpxNamespace.paragraph,
            "pos": HwpxNamespace.paragraph,
            "outMargin": HwpxNamespace.paragraph,
            "extent": HwpxNamespace.core,
        ]
        let depthLimit = context.unknownDepthLimit
        // offset·orgSz·curSz·flip·rotationInfo·renderingInfo·lineShape 등은 렌더에
        // 반영되지 않으므로 조용히 사라지면 안 된다.
        var unknownChildren = node.unconsumedChildRecords(
            consumed: consumed, maxDepth: depthLimit
        )
        // 네 이름 모두 단일 조회다 — 둘째 등장부터는 읽히지 않으므로 강등한다.
        unknownChildren += node.duplicateSingletonRecords(
            of: consumed, maxDepth: depthLimit
        )
        // 속성만 읽는 잎 래퍼다 — 자식이 오면 전부 미소비라 여기서 강등해야
        // 진단에 남는다.
        for wrapperName in ["sz", "pos", "outMargin"] {
            if let wrapper = node.paragraphFirstChild(named: wrapperName) {
                unknownChildren += wrapper.unconsumedChildRecords(
                    consumed: [], maxDepth: depthLimit
                )
            }
        }
        if let extent = node.coreFirstChild(named: "extent") {
            unknownChildren += extent.unconsumedChildRecords(
                consumed: [], maxDepth: depthLimit
            )
        }
        return unknownChildren
    }

    /// 표 118 실물 레이아웃 26바이트 — 속성 UINT32 + extent INT32×2 + BinData ID
    /// UINT16 + 테두리 색 COLORREF + 테두리 두께 INT32 + 테두리 속성 UINT32.
    static func oleBytes(
        _ node: HwpxXMLNode,
        common: HwpCommonCtrlProperty,
        binItemId: UInt16
    ) -> Data {
        var payload = Data(capacity: 26)
        payload.appendHwpxLittleEndian(Self.property(node))
        let extent = Self.extent(node, common: common)
        payload.appendHwpxLittleEndian(UInt32(bitPattern: extent.x))
        payload.appendHwpxLittleEndian(UInt32(bitPattern: extent.y))
        payload.appendHwpxLittleEndian(binItemId)
        payload.appendHwpxLittleEndian(UInt32(0)) // 테두리 색
        payload.appendHwpxLittleEndian(UInt32(0)) // 테두리 두께 (0 = 없음)
        payload.appendHwpxLittleEndian(UInt32(0)) // 테두리 속성 (표 87)
        return payload
    }

    /// 표 119 OLE 개체 속성의 속성 — bit 0-7 DVASPECT, bit 8 moniker, bit 9-15
    /// 베이스라인(0 = 기본 85%), bit 16-21 개체 종류.
    static func property(_ node: HwpxXMLNode) -> UInt32 {
        // 생략은 CONTENT — MFC `COleClientItem::m_nDrawAspect`의 기본값이고 한글.app
        // 저장본이 쓰는 유일한 값이다. 미지 이름은 0으로 둔다 (추측하지 않는다).
        let drawAspect = drawAspects[node.attribute("drawAspect") ?? "CONTENT"] ?? 0
        let moniker: UInt32 = node.boolAttribute("hasMoniker") ? 1 << 8 : 0
        let objectType = objectTypes[node.attribute("objectType") ?? "UNKNOWN"] ?? 0
        let baseline = Self.baseline(node, objectType: objectType)
        return drawAspect | moniker | (baseline << 9) | (objectType << 16)
    }

    /// `eqBaseLine` → 표 119 bit 9-15 베이스라인 코드.
    ///
    /// 스펙은 raw 0을 "디폴트(85%)", 1~101을 0~100%로 적고 **"현재는 수식만이
    /// 베이스라인을 별도로 가진다"**고 명시한다. HWPX 쪽 값이 퍼센트라는 근거는
    /// 한컴 모델이 그 속성을 85로 초기화해 직렬화한다는 것이다
    /// (`OWPML/Class/Para/OLEType.cpp`의 `m_uEqBaseLine(85)`; 공개 모델에 XSD는
    /// 없어 스키마 기본값은 확인할 수 없다) — raw를 담는 속성이었다면 기본값은
    /// "디폴트"를 뜻하는 0이었을 것이고, 하필 스펙이 디폴트로 명시한 85%와 같은
    /// 수가 나올 이유가 없다. 그래서 **수식 개체의 명시값만** 0~100으로 좁혀
    /// `+1`로 인코딩한다.
    ///
    /// 수식이 아닌 개체는 값을 그대로 싣는다. 스펙상 베이스라인을 갖지 않는
    /// 종류이고, chart 변환 쌍이 그 경로의 실측이다 — HWPX `eqBaseLine="0"`인
    /// 문서의 HWP payload 속성이 0x00000001(베이스라인 비트 0)이라 여기에 +1을
    /// 걸면 한글.app이 쓴 바이트와 어긋난다 (한글.app이 안 쓰는 필드를 양쪽에서
    /// 0으로 적을 뿐이다).
    ///
    /// 생략·형식 오류는 raw 0이다 — 수식이든 아니든 "디폴트 85%"가 맞는 뜻이고,
    /// 모델 기본값 85(= 85%)와도 같은 결과다.
    static func baseline(_ node: HwpxXMLNode, objectType: UInt32) -> UInt32 {
        guard let raw = node.attribute("eqBaseLine"), let percent = Int(raw) else {
            return 0
        }
        guard objectType == equationObjectType else {
            // 7비트 필드라 범위 밖은 클램프한다 (해석하지 않는 값의 보존).
            return UInt32(min(127, max(0, percent)))
        }
        return UInt32(min(100, max(0, percent))) + 1
    }

    /// `hc:extent`(개체 자체 크기) — 없으면 개체 크기(`hp:sz`)로 합성한다
    /// (그림의 imgRect 폴백과 같은 규칙).
    static func extent(
        _ node: HwpxXMLNode,
        common: HwpCommonCtrlProperty
    ) -> (x: Int32, y: Int32) {
        let width = Int32(clamping: common.width)
        let height = Int32(clamping: common.height)
        guard let extent = node.coreFirstChild(named: "extent") else {
            return (width, height)
        }
        return (
            extent.int32Attribute("x", default: width),
            extent.int32Attribute("y", default: height)
        )
    }

    /// OWPML `drawAspect` → 표 119 bit 0-7 (DVASPECT_*). 실측은 CONTENT뿐이고
    /// 이름은 한컴 공개 OWPML 모델의 직렬화 표 `g_OleDrawAspectList`
    /// (`OWPML/Class/enumdef.h`)를 그대로 쓴다 — **밑줄이 있는 `THUMB_NAIL`·
    /// `DOC_PRINT`가 실제 저장 문자열이다**. 붙여 쓴 표기를 별칭으로 받지 않는
    /// 것은 다른 열거 매퍼와 같은 규약이다 (스키마에 없는 이름은 0).
    static let drawAspects: [String: UInt32] = [
        "CONTENT": 1, "THUMB_NAIL": 2, "ICON": 4, "DOC_PRINT": 8,
    ]

    /// 표 119 bit 16-21의 수식 개체 — 베이스라인을 갖는 유일한 종류다
    /// (`baseline(_:objectType:)`의 게이트).
    static let equationObjectType: UInt32 = 4

    /// OWPML `objectType` → 표 119 bit 16-21 개체 종류. 실측은 UNKNOWN뿐이고
    /// 나머지 이름·값은 한컴 모델의 `g_OleObjectList`·`OLEOBJECTTYPE`이 표 119
    /// 나열 순서와 일치함을 확인해 채웠다.
    static let objectTypes: [String: UInt32] = [
        "UNKNOWN": 0, "EMBEDDED": 1, "LINK": 2, "STATIC": 3,
        "EQUATION": equationObjectType,
    ]
}

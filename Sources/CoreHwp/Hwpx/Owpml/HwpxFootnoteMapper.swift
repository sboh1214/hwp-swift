import Foundation

/// `hp:footNote`·`hp:endNote`(각주·미주)를 `.footnote`·`.endnote(HwpListControl)`로,
/// 그 본문 문단 안의 `hp:autoNum`을 `.autoNumber(HwpOtherControl)`로 옮긴다 —
/// 구역 부속 컨트롤(제어 문자 코드 17)과 자동 번호(코드 18)의 typed 승격이다 (#168).
///
/// 강등 상태에서는 **각주·미주 본문이 통째로 사라진다**: 조판이 `.footnote`/`.endnote`
/// 컨트롤에서만 주석을 모으고(`HwpFootnoteCoordinator`), `.notImplemented`는
/// 리스트 문단 모델 자체가 없어 그릴 것이 남지 않는다. 미지 요소 강등이
/// 요소 이름만 payload로 담기 때문에 `hp:t` 텍스트도 함께 버려진다.
///
/// **`hp:autoNum` 동반 승격은 선택이 아니다.** 본문 위 첨자 참조 번호는 컨트롤
/// 종류만 보는 경로에서 나오지만(`HwpFootnoteCoordinatorPlacement`), 각주 영역
/// 본문 첫머리의 번호 라벨은 `HwpTextRunBuilder.autoNumberReplacements`가
/// `.autoNumber` 컨트롤의 `autoNumberInfo`를 찾아야 만들어진다. 각주만 승격하면
/// 번호 없는 각주가 된다.
///
/// ## 실측 (2026-09-07, 한컴오피스 한글 12.30.0 macOS)
///
/// `footnote-endnote` 픽스처의 사본을 `한글 표준 문서 (*.hwpx)`로 저장한 변환본과
/// 그 HWP 쌍의 레코드 payload를 나란히 읽었다.
///
/// ```xml
/// <hp:footNote number="1" suffixChar="41" instId="1115242634">
///   <hp:subList vertAlign="TOP" textWidth="0" textHeight="0" …>
///     <hp:p …><hp:run charPrIDRef="3">
///       <hp:ctrl><hp:autoNum num="1" numType="FOOTNOTE">
///         <hp:autoNumFormat type="DIGIT" userChar="" prefixChar="" suffixChar=")" supscript="0"/>
///       </hp:autoNum></hp:ctrl>
///       <hp:t> CoreHwp footnote fixture</hp:t>
/// ```
///
/// ↔ HWP 쌍 `fn  ` 컨트롤 헤더 20바이트
/// `20 20 6E 66 | 01 00 00 00 | 00 00 | 29 00 | 00 00 00 00 | 8A 40 79 42`,
/// 리스트 헤더 16바이트 `01 00 00 00 | 00×12`, `atno` 16바이트
/// `6F 6E 74 61 | 01 00 00 00 | 01 00 | 00 00 | 00 00 | 29 00`.
///
/// 기본값이 아닌 두 번째 표본(같은 문서의 미주 모양을 대화상자에서
/// `㉠,㉡,㉢` + 앞 `[` · 뒤 `]` + 시작 번호 3 + 구역의 끝 + 작게로 바꿔 저장)이
/// 나머지 자리를 확정했다 — `<hp:endNote flag="11" number="3" prefixChar="91"
/// suffixChar="93" instId="1115242635">` ↔
/// `20 20 6E 65 | 03 00 00 00 | 5B 00 | 5D 00 | 0B 00 00 00 | 8B 40 79 42`.
/// 즉 오프셋 8-9가 앞 장식, 12-15가 `flag`다.
///
/// **`@suffixChar`는 이름이 같아도 인코딩이 다르다** — `hp:footNote`/`hp:endNote`의
/// 것은 10진 코드포인트 문자열("41")이고 `hp:autoNumFormat`의 것은 리터럴 문자(")")다.
/// 하나의 읽기로 뭉뚱그리면 `)`가 0으로, 41이 문자 '4'로 접힌다.
enum HwpxFootnoteMapper {
    /// 제어 문자 코드 17(각주·미주) 앵커 + typed 컨트롤 — `classify`의 분기.
    static func anchor(
        _ node: HwpxXMLNode,
        isEndnote: Bool,
        context: HwpxMappingContext
    ) throws -> HwpxRunChildAction {
        let list = try map(node, isEndnote: isEndnote, context: context)
        return .anchor(
            code: 17,
            fourCC: isEndnote
                ? HwpOtherCtrlId.endnote.rawValue
                : HwpOtherCtrlId.footnote.rawValue,
            ctrl: isEndnote ? .endnote(list) : .footnote(list)
        )
    }

    static func map(
        _ node: HwpxXMLNode,
        isEndnote: Bool,
        context: HwpxMappingContext
    ) throws -> HwpListControl {
        let fourCC = isEndnote
            ? HwpOtherCtrlId.endnote.rawValue
            : HwpOtherCtrlId.footnote.rawValue
        let depthLimit = context.unknownDepthLimit

        // 실측 20바이트: ctrl id + 번호 UINT32 + 앞/뒤 장식 WCHAR + flag UINT32 +
        // 생성 번호 UINT32. 조판은 이 중 아무것도 되읽지 않지만(적용 범위를
        // 되읽는 머리말과 다르다) 바이너리와 같은 모양이어야 왕복이 성립한다.
        var payload = Data(capacity: 20)
        payload.appendHwpxLittleEndian(fourCC)
        payload.appendHwpxLittleEndian(node.uint32Attribute("number", default: 0))
        payload.appendHwpxLittleEndian(node.uint16Attribute("prefixChar", default: 0))
        payload.appendHwpxLittleEndian(node.uint16Attribute("suffixChar", default: 0))
        payload.appendHwpxLittleEndian(node.uint32Attribute("flag", default: 0))
        payload.appendHwpxLittleEndian(node.uint32Attribute("instId", default: 0))

        var unknowns = node.unconsumedChildRecords(
            consumed: ["subList"], in: HwpxNamespace.paragraph, maxDepth: depthLimit
        )
        unknowns += node.duplicateSingletonRecords(
            of: ["subList"], in: HwpxNamespace.paragraph, maxDepth: depthLimit
        )

        return HwpListControl(
            header: HwpCtrlHeader(
                ctrlId: fourCC,
                // `HwpListControl.load`가 ctrl id와 무관하게 `decoupledPayload`를
                // 쓰므로(양 모드 보존) HWPX도 같은 부류여야 패리티다 — 되읽는
                // 소비자가 없다고 `preservedPayload`로 게이트하면 바이너리가
                // 들고 있는 바이트를 HWPX만 비우는 반대 방향 격차가 생긴다.
                rawPayload: context.options.decoupledPayload(payload),
                unknownChildren: []
            ),
            listArray: [try mapList(node.paragraphFirstChild(named: "subList"), context: context)],
            unknownChildren: unknowns
        )
    }

    /// `hp:subList` → 리스트 하나. subList가 없어도 빈 리스트를 반드시 만든다 —
    /// 바이너리 `HwpListControl.load`는 리스트가 하나도 없으면 던지고
    /// (`recordDoesNotExist`) 문단 조립이 `.other`로 강등한다.
    private static func mapList(
        _ subList: HwpxXMLNode?,
        context: HwpxMappingContext
    ) throws -> HwpListControlList {
        let listContext = try context.descending()
        let paragraphNodes = subList?.paragraphChildren(named: "p") ?? []
        var paragraphs: [HwpParagraph] = []
        paragraphs.reserveCapacity(paragraphNodes.count)
        for (index, paragraphNode) in paragraphNodes.enumerated() {
            paragraphs.append(try HwpxParagraphMapper.map(
                paragraphNode,
                context: listContext,
                isLastInList: index == paragraphNodes.count - 1
            ))
        }

        // 표 89 세로 정렬 — 각주·미주 subList는 실물이 `TOP`(속성 0)이다.
        var listProperty = HwpListHeaderProperty()
        listProperty.verticalAlignment = HwpxTableMapper.verticalAlignments[
            subList?.attribute("vertAlign") ?? "TOP"
        ] ?? .top
        listProperty.verticalAlignmentRawValue = listProperty.verticalAlignment?.rawValue ?? 0
        listProperty.rawValue = listProperty.synthesizedRawValue

        // 실측 16바이트: 문단 수 INT32 + 속성 UINT32 + 0 8바이트. 머리말·꼬리말의
        // 34바이트(textWidth·textHeight를 실은 꼴)와 다르다 — 각주 subList는
        // 실물이 `textWidth="0" textHeight="0"`이고 바이너리에도 그 자리가 없다.
        var listPayload = Data(capacity: 16)
        listPayload.appendHwpxLittleEndian(UInt32(bitPattern: Int32(paragraphs.count)))
        listPayload.appendHwpxLittleEndian(listProperty.rawValue)
        listPayload.append(Data(repeating: 0, count: 8))

        var listUnknowns: [HwpUnknownRecord] = []
        if let subList {
            listUnknowns = subList.unconsumedChildRecords(
                consumed: ["p"], in: HwpxNamespace.paragraph, maxDepth: context.unknownDepthLimit
            )
        }

        return HwpListControlList(
            header: try HwpListHeader.load(listPayload, options: context.options),
            headerRawPayload: context.options.decoupledPayload(listPayload),
            headerUnknownChildren: listUnknowns,
            paragraphArray: paragraphs
        )
    }
}

// MARK: - 자동 번호 (`hp:autoNum` → `atno`, 표 142)

extension HwpxFootnoteMapper {
    /// 제어 문자 코드 18(자동 번호) 앵커 + typed 컨트롤.
    ///
    /// `hp:newNum`(새 번호 지정)은 같은 코드를 쓰지만 표 144의 다른 payload라
    /// 이번 승격 범위 밖이다 (#169) — `sectionAttachments`에 남는다.
    static func autoNumberAnchor(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpxRunChildAction {
        .anchor(
            code: 18,
            fourCC: HwpOtherCtrlId.autoNumber.rawValue,
            ctrl: .autoNumber(try mapAutoNumber(node, context: context))
        )
    }

    /// 표 142 자동 번호: ctrl id + 속성 UINT32(표 143) + 번호 UINT16 +
    /// 사용자 기호·앞/뒤 장식 WCHAR = 16바이트.
    ///
    /// 합성한 payload를 바이너리 로더(`HwpOtherControl.init(_:_:)`)에 그대로
    /// 태워 typed 뷰와 게이트를 한 번에 얻는다 — 그 로더는 `rawTrailing`·
    /// `rawPayload`만 뷰어 게이트에 걸고 `autoNumberInfo`는 **게이트 전 원본**에서
    /// 만들므로, 직접 세우면 `.viewer`에서 번호 라벨이 사라지는 비대칭이 생긴다.
    static func mapAutoNumber(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpOtherControl {
        let format = node.paragraphFirstChild(named: "autoNumFormat")
        var property = autoNumberKinds[node.attribute("numType") ?? "PAGE"] ?? 0
        property |= UInt32(HwpxNumberFormatMapper.code(for: format?.attribute("type")) & 0xFF) << 4
        if format?.boolAttribute("supscript") == true {
            property |= 1 << 12
        }

        var payload = Data(capacity: 16)
        payload.appendHwpxLittleEndian(HwpOtherCtrlId.autoNumber.rawValue)
        payload.appendHwpxLittleEndian(property)
        payload.appendHwpxLittleEndian(node.uint16Attribute("num", default: 0))
        payload.appendHwpxLittleEndian(literalWchar(format?.attribute("userChar")))
        payload.appendHwpxLittleEndian(literalWchar(format?.attribute("prefixChar")))
        payload.appendHwpxLittleEndian(literalWchar(format?.attribute("suffixChar")))

        var reader = DataReader(payload, options: context.options)
        var control = try HwpOtherControl(&reader, [])
        control.unknownChildren = node.unconsumedChildRecords(
            consumed: ["autoNumFormat"], in: HwpxNamespace.paragraph,
            maxDepth: context.unknownDepthLimit
        )
        control.unknownChildren += node.duplicateSingletonRecords(
            of: ["autoNumFormat"], in: HwpxNamespace.paragraph,
            maxDepth: context.unknownDepthLimit
        )
        if let format {
            control.unknownChildren += format.unconsumedChildRecords(
                consumed: [], maxDepth: context.unknownDepthLimit
            )
        }
        return control
    }

    /// `hp:autoNum numType` → 표 143 bits 0-3. 실측은 `FOOTNOTE`↔1·`ENDNOTE`↔2이고
    /// 나머지는 `HwpAutoNumberKind` 나열 순서를 따랐다. 미지 이름은 0(쪽 번호)으로
    /// 접는다 — 각주·미주가 아닌 종류는 번호 치환 대상이 아니라서, 모르는 값을
    /// 각주로 넘겨 없던 번호를 지어내는 것보다 안전하다.
    static let autoNumberKinds: [String: UInt32] = [
        "PAGE": 0, "FOOTNOTE": 1, "ENDNOTE": 2,
        "PICTURE": 3, "TABLE": 4, "EQUATION": 5,
    ]

    /// 리터럴 문자 속성(`hp:autoNumFormat`의 장식 문자)을 WCHAR로 읽는다.
    /// 빈 문자열·비BMP는 0(없음)이다 — 반쪽 서러게이트를 실으면 `String` 복원이
    /// 문서에 없던 U+FFFD 글리프를 만든다 (글머리표 문자와 같은 규약).
    static func literalWchar(_ text: String?) -> UInt16 {
        guard let text, let scalar = text.unicodeScalars.first, scalar.value <= 0xFFFF else {
            return 0
        }
        return UInt16(scalar.value)
    }
}

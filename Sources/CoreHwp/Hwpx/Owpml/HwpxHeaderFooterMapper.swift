import Foundation

/// `hp:header`·`hp:footer`(머리말·꼬리말)를 `.header`·`.footer(HwpListControl)`로
/// 옮긴다 — 구역 부속 컨트롤(제어 문자 코드 16)의 typed 승격이다 (#167).
///
/// 강등 상태에서는 머리말·꼬리말이 **매 쪽에서 통째로 사라진다**:
/// `HwpPageChromeBuilder.register`가 `.header`/`.footer`만 활성 밴드로 받고,
/// `.notImplemented`는 문단 모델 자체가 없어 그릴 것이 남지 않는다.
///
/// 조판이 읽는 값은 둘뿐이다 — 적용 범위(`HwpListControl.headerFooterApplyScope`)와
/// 리스트 문단(`listArray.flatMap(\.paragraphArray)`). 그래서
/// **컨트롤 헤더 payload는 렌더 필수다**: 적용 범위가 `header.rawPayload`의
/// 오프셋 4에서 UINT32를 다시 읽어 하위 2비트를 보기 때문이다(표 141).
/// 바이너리 로더(`HwpListControl.load`)가 같은 이유로 그 payload를
/// `decoupledPayload`로 보존하므로 여기서도 **양 모드 보존**한다 —
/// `preservedPayload` 게이트를 쓰면 `.viewer`에서 적용 범위가 사라져
/// 홀·짝수 머리말이 전부 양쪽으로 그려진다.
///
/// 실측 근거: `header-footer` 픽스처의 사본을 한컴오피스 한글 12.30.0
/// (build 6446) macOS에서 `한글 표준 문서 (*.hwpx)`로 저장해 확인했다.
///
/// ```xml
/// <hp:header id="1" applyPageType="BOTH">
///   <hp:subList id="" textDirection="HORIZONTAL" lineWrap="BREAK" vertAlign="TOP"
///               linkListIDRef="0" linkListNextIDRef="0"
///               textWidth="42520" textHeight="4252" hasTextRef="0" hasNumRef="0">
///     <hp:p …><hp:run charPrIDRef="2"><hp:t>CoreHwp header fixture</hp:t></hp:run>…</hp:p>
///   </hp:subList>
/// </hp:header>
/// ```
///
/// `hp:footer`는 같은 구조에 `vertAlign="BOTTOM"`이다. 문단 안 `hp:linesegarray`도
/// 본문 문단과 같은 경로로 매핑되므로 조판 캐시가 그대로 살아난다.
enum HwpxHeaderFooterMapper {
    /// 제어 문자 코드 16(머리말·꼬리말) 앵커 + typed 컨트롤 — `classify`의 분기.
    static func anchor(
        _ node: HwpxXMLNode,
        isFooter: Bool,
        context: HwpxMappingContext
    ) throws -> HwpxRunChildAction {
        let list = try map(node, isFooter: isFooter, context: context)
        return .anchor(
            code: 16,
            fourCC: isFooter
                ? HwpOtherCtrlId.footer.rawValue
                : HwpOtherCtrlId.header.rawValue,
            ctrl: isFooter ? .footer(list) : .header(list)
        )
    }

    static func map(
        _ node: HwpxXMLNode,
        isFooter: Bool,
        context: HwpxMappingContext
    ) throws -> HwpListControl {
        let fourCC = isFooter
            ? HwpOtherCtrlId.footer.rawValue
            : HwpOtherCtrlId.header.rawValue
        let subList = node.paragraphFirstChild(named: "subList")
        let depthLimit = context.unknownDepthLimit

        // 표 140: ctrl id(4바이트) 뒤에 속성 UINT32. 표 141 bits 0-1이 적용
        // 범위이고 나머지 비트는 실물에서 0이다. 8바이트를 채워야
        // `headerFooterApplyScope`의 오프셋 4 읽기가 성립한다.
        var payload = Data(capacity: 8)
        payload.appendHwpxLittleEndian(fourCC)
        payload.appendHwpxLittleEndian(UInt32(applyScope(of: node).rawValue))

        var unknowns = node.unconsumedChildRecords(
            consumed: ["subList"], in: HwpxNamespace.paragraph, maxDepth: depthLimit
        )
        unknowns += node.duplicateSingletonRecords(
            of: ["subList"], in: HwpxNamespace.paragraph, maxDepth: depthLimit
        )

        return HwpListControl(
            header: HwpCtrlHeader(
                ctrlId: fourCC,
                // 바이너리와 같은 decoupled 부류 — 렌더가 되읽으므로 비우지 않는다.
                rawPayload: context.options.decoupledPayload(payload),
                unknownChildren: []
            ),
            listArray: [try mapList(subList, context: context)],
            unknownChildren: unknowns
        )
    }

    /// `hp:subList` → 리스트 하나. subList가 없으면 문단 없는 빈 리스트를 만든다 —
    /// 바이너리 `HwpListControl.load`는 리스트가 하나도 없으면 던지므로
    /// (`recordDoesNotExist`) 여기서도 리스트 자체는 반드시 만든다.
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

        // 표 89 세로 정렬 — 머리말은 TOP, 꼬리말은 BOTTOM이 실물이다.
        // `synthesizedRawValue`는 스펙 자리(bits 0-6)에 쓴다 (HWPX는 윈도우
        // 저장본의 상위 레이아웃이 아니다 — `HwpListHeaderProperty` 참조).
        var listProperty = HwpListHeaderProperty()
        listProperty.verticalAlignment = HwpxTableMapper.verticalAlignments[
            subList?.attribute("vertAlign") ?? "TOP"
        ] ?? .top
        listProperty.verticalAlignmentRawValue = listProperty.verticalAlignment?.rawValue ?? 0
        listProperty.rawValue = listProperty.synthesizedRawValue

        // 표 89 payload: 문단 수 INT32 + 속성 UINT32. 바이너리 로더와 같은
        // 모양으로 합성해 `HwpListHeader.load`가 typed 필드를 세우게 한다.
        var listPayload = Data(capacity: 8)
        listPayload.appendHwpxLittleEndian(UInt32(bitPattern: Int32(paragraphs.count)))
        listPayload.appendHwpxLittleEndian(listProperty.rawValue)

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

    /// `applyPageType` → 표 141 bits 0-1. 생략은 OWPML 기본값 `BOTH`이고,
    /// 미지 이름도 양쪽으로 접는다 — 범위를 추측해 쪽을 건너뛰면 머리말이
    /// 통째로 사라지므로, 모르면 그리는 쪽이 안전하다.
    static func applyScope(of node: HwpxXMLNode) -> HwpHeaderFooterApplyScope {
        applyPageTypes[node.attribute("applyPageType") ?? "BOTH"] ?? .bothPages
    }

    static let applyPageTypes: [String: HwpHeaderFooterApplyScope] = [
        "BOTH": .bothPages,
        "EVEN": .evenPagesOnly,
        "ODD": .oddPagesOnly,
    ]
}

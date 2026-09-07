import Foundation

/// `hp:newNum`·`hp:pageHiding`·`hp:bookmark`·`hp:indexmark`(새 번호 지정·쪽
/// 감추기·책갈피·찾아보기 표식)를 typed 컨트롤로 옮긴다 — 구역 부속 컨트롤
/// 승격의 마지막 조각이다 (#169, 상위 #163).
///
/// 넷 다 바이너리 쪽에 typed 뷰가 이미 있고(`HwpOtherControl`의
/// `newNumberInfo`·`pageHideInfo`·`indexmarkInfo`·`bookmarkInfo`) 소비자도 있다 —
/// 새 번호는 `HwpPaginator.applyNewNumbers`가 쪽·각주·미주 카운터를 되돌리고,
/// 쪽 감추기는 `HwpPageChromeBuilder`의 `pageHideMask`가 머리말·꼬리말·쪽 번호를
/// 지우며, 책갈피는 `HwpOutlineCollector`가 탐색 목록에 싣는다. 강등 상태에서는
/// 그 셋이 전부 무시돼 **HWP 쌍과 다른 쪽 번호·다른 크롬**이 나온다.
///
/// ## 실측 (2026-09-08, 한컴오피스 한글 12.30.0 macOS)
///
/// `section-marks` 쌍(같은 문서를 `한글 문서 (*.hwp)`와 `한글 표준 문서 (*.hwpx)`로
/// 각각 저장)의 레코드 payload를 나란히 읽었다. XML ↔ 바이너리 대응은 이렇다.
///
/// ```xml
/// <hp:pageHiding hideHeader="1" hideFooter="0" hideMasterPage="0"
///                hideBorder="1" hideFill="0" hidePageNum="1"/>   <!-- 0x29 -->
/// <hp:pageHiding hideHeader="0" hideFooter="1" hideMasterPage="1"
///                hideBorder="0" hideFill="1" hidePageNum="0"/>   <!-- 0x16 -->
/// <hp:newNum num="9" numType="PAGE"/>        <!-- 6F 6E 77 6E 00 00 00 00 09 00 -->
/// <hp:newNum num="5" numType="PICTURE"/>     <!-- …          03 00 00 00 05 00 -->
/// <hp:newNum num="7" numType="FOOTNOTE"/>    <!-- …          01 00 00 00 07 00 -->
/// <hp:bookmark name="표식 A1"/>
/// <hp:indexmark><hp:firstKey>본문</hp:firstKey></hp:indexmark>
/// ```
///
/// **쪽 감추기 두 표본이 표 145의 여섯 비트를 전부 확정한다** — 하나가
/// `머리말+쪽 테두리+쪽 번호`(0x29 = bits 0·3·5), 다른 하나가
/// `꼬리말+바탕쪽+쪽 배경`(0x16 = bits 1·2·4)이라 서로의 여집합이다. 비트 순서는
/// 한컴 공개 모델이 적은 속성 순서(`pageHiding.cpp`의 hideHeader→hidePageNum)와도,
/// 표 132를 옮긴 `HwpSectionDefProperty`의 bits 0-5와도 같다. 저장소의 실물
/// `.hwp` 3건이 전부 0x20뿐이라 그 전에는 bit 5 말고는 추론이었다.
///
/// **`nwno`의 제어 문자 코드는 18이 아니라 21이다** — 코드 18은 자동 번호(`atno`)
/// 전용이고 새 번호는 쪽 컨트롤 가족(21)이다. 저장소 실물 36종 전수 집계가
/// `atno` 3,436건 전부 18 · `nwno` 41건 전부 21 · `pghd` 3건과 `pgnp` 4건 전부 21로
/// 갈리고, 이번 실측 쌍도 `<E21:nwno>`다. 강등 표가 18로 적고 있었고(#169 이슈 표도
/// 같은 오기) 승격이 그 값을 그대로 물려받을 뻔했다.
///
/// **`idxm`의 문자열 뒤 6바이트**는 두 번째 키워드 길이 WORD(둘 다 0) + UINT32다.
/// 그 UINT32를 한글 12.30은 `FF FF FF FF`로, 레거시 문서(헌법주석 35건)는 0으로
/// 적는다. OWPML `hp:indexmark`에는 대응 속성이 아예 없어(속성 0개, 자식이
/// `hp:firstKey`·`hp:secondKey`뿐) 어느 쪽도 XML에서 복원할 수 없으므로, 우리
/// HWPX 입력을 실제로 만들어 내는 저작기(12.30)의 값을 고정한다. 이 자리는
/// `indexmarkInfo.rawTrailing`에만 남고 읽는 소비자가 없다.
///
/// **책갈피 이름은 컨트롤 payload가 아니라 `CTRL_DATA` 자식**에 있다 —
/// ParameterSet `0x021B` · item id `0x4000_0000` · value type 1의 문자열이다
/// (컨트롤 헤더는 4CC 4바이트가 전부). 그래서 합성 레코드를 `HwpOtherControl`의
/// 바이너리 이니셜라이저에 자식으로 태운다 — `bookmarkInfo`가 `ctrlDataRecords`를
/// 거쳐 만들어지므로 typed 필드를 직접 세우면 게이트·파생이 어긋난다.
enum HwpxSectionMarkMapper {
    /// OWPML 요소 이름 → (제어 문자 코드, 4CC). 코드는 위 실측이 정본이다.
    static let marks: [String: (code: UInt16, fourCC: UInt32)] = [
        "newNum": (21, HwpOtherCtrlId.newNumber.rawValue),
        "pageHiding": (21, HwpOtherCtrlId.pageHide.rawValue),
        "bookmark": (22, HwpOtherCtrlId.bookmark.rawValue),
        "indexmark": (22, HwpOtherCtrlId.indexmark.rawValue),
    ]

    /// `hp:pageHiding`의 불리언 속성 → 표 145 비트 번호(배열 인덱스).
    /// 이름과 순서 모두 한컴 공개 모델 `OWPML/Class/Para/pageHiding.cpp`의
    /// `SetAttribute` 나열이고, 생략 기본값은 전부 false다.
    static let pageHideAttributes = [
        "hideHeader", "hideFooter", "hideMasterPage",
        "hideBorder", "hideFill", "hidePageNum",
    ]

    /// 제어 문자 앵커 + typed 컨트롤 — `HwpxControlMapper.classify`의 분기.
    ///
    /// 표에 없는 이름은 `.unknown`이다. `classify`가 네 이름으로만 부르므로
    /// 닿지 않는 가지이고, 앵커를 지어내는 것보다 위치 불확실 강등이 안전하다.
    static func anchor(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpxRunChildAction {
        guard let slot = marks[node.localName] else {
            return .unknown
        }
        let typed = try control(node, context: context)
        return .anchor(
            code: slot.code,
            fourCC: slot.fourCC,
            // typed 매핑이 성립하지 않으면 **자리는 지키고** 강등한다 —
            // 코드와 4CC가 그대로라 WCHAR/ctrl 슬롯 정렬이 유지되고
            // `parseDiagnostics()`가 요소 이름까지 보고한다.
            ctrl: typed ?? HwpxControlMapper.degradedControl(
                fourCC: slot.fourCC, element: node, maxDepth: context.unknownDepthLimit
            )
        )
    }

    /// 네 요소의 typed 컨트롤. 승격이 **강등보다 나쁜 출력**을 낼 조건에서만
    /// nil을 돌려 강등으로 되돌린다.
    private static func control(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpCtrlId? {
        switch node.localName {
        case "newNum":
            try newNumber(node, context: context).map { .newNumber($0) }
        case "pageHiding":
            try pageHide(node, context: context).map { .pageHide($0) }
        case "bookmark":
            try bookmark(node, context: context).map { .bookmark($0) }
        case "indexmark":
            try indexmark(node, context: context).map { .indexmark($0) }
        default:
            nil
        }
    }

    // MARK: - 새 번호 지정 (`hp:newNum` → `nwno`, 표 144)

    /// 표 144: ctrl id + 속성 UINT32(bits 0-3 번호 종류, 표 143) + 번호 UINT16
    /// = 10바이트. 표 142 자동 번호(16바이트)와 달리 장식 문자 자리가 없다.
    ///
    /// **표 143이 담지 못하는 번호 종류는 승격하지 않는다.** `TOTAL_PAGE`(값 6)를
    /// 실으면 `HwpAutoNumberKind`가 0-5뿐이라 `.page`로 접히는데, 새 번호의
    /// `.page`는 `HwpPaginator`의 `pendingPageNumber`를 갈아 **그 뒤 모든 쪽의
    /// 번호를 바꾼다** — 자동 번호가 한 자리를 틀리게 그리던 #168보다 피해가
    /// 크다. 강등 상태에는 아예 없던 오작동이므로 `autoNumberKinds`에 없는
    /// 이름은 강등으로 되돌린다.
    ///
    /// 생략 기본값은 한컴 공개 모델의 생성자 값이다 — `hp:autoNum`과 같은 클래스
    /// (`CAutoNumNewNumType`)라 `m_nNum(1)`·`m_uNumType(ANT_PAGE)`이고,
    /// `GetAttribute`는 속성이 없으면 값을 건드리지 않는다.
    ///
    /// 모델이 `hp:autoNumFormat` 자식을 등록하지만 표 144에는 그 자리가 없다 —
    /// 소비하지 않고 미지 자식으로 남겨 진단에 보고한다(실물 쌍에는 없다).
    private static func newNumber(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpOtherControl? {
        guard let kind = HwpxFootnoteMapper.autoNumberKinds[
            node.attribute("numType") ?? "PAGE"
        ] else {
            return nil
        }

        var payload = Data(capacity: 10)
        payload.appendHwpxLittleEndian(HwpOtherCtrlId.newNumber.rawValue)
        payload.appendHwpxLittleEndian(kind)
        payload.appendHwpxLittleEndian(node.uint16Attribute("num", default: 1))
        return try loaded(payload, node: node, consumed: [], context: context)
    }

    // MARK: - 쪽 감추기 (`hp:pageHiding` → `pghd`, 표 145)

    /// 표 145: ctrl id + 감추기 bit field UINT32 = 8바이트.
    private static func pageHide(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpOtherControl? {
        var mask: UInt32 = 0
        for (bit, name) in pageHideAttributes.enumerated() where node.boolAttribute(name) {
            mask |= 1 << UInt32(bit)
        }

        var payload = Data(capacity: 8)
        payload.appendHwpxLittleEndian(HwpOtherCtrlId.pageHide.rawValue)
        payload.appendHwpxLittleEndian(mask)
        return try loaded(payload, node: node, consumed: [], context: context)
    }

    // MARK: - 책갈피 (`hp:bookmark` → `bokm` + CTRL_DATA)

    /// 컨트롤 헤더는 4CC 4바이트뿐이고 이름은 `CTRL_DATA` 자식의 ParameterSet에
    /// 있다 — setId `0x021B` + item 수 1 + item id `0x4000_0000` + value type 1 +
    /// 길이 WORD + WCHAR 배열 (실측 22바이트: `1B 02 01 00 00 00 00 40 01 00 05 00`
    /// + `표식 A1`).
    private static func bookmark(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpOtherControl? {
        guard let units = wcharUnits(node.attribute("name") ?? "") else {
            return nil
        }

        var parameterSet = Data(capacity: 12 + units.count * 2)
        parameterSet.appendHwpxLittleEndian(UInt16(0x021B))
        parameterSet.appendHwpxLittleEndian(UInt16(1))
        parameterSet.appendHwpxLittleEndian(UInt32(0x4000_0000))
        parameterSet.appendHwpxLittleEndian(UInt16(1))
        parameterSet.appendHwpxLittleEndian(WORD(units.count))
        for unit in units {
            parameterSet.appendHwpxLittleEndian(unit)
        }

        var payload = Data(capacity: 4)
        payload.appendHwpxLittleEndian(HwpOtherCtrlId.bookmark.rawValue)
        return try loaded(
            payload, node: node, consumed: [], context: context,
            children: [HwpRecord(
                tagId: HwpSectionTag.ctrlData.rawValue,
                level: 0,
                payload: parameterSet,
                options: context.options
            )]
        )
    }

    // MARK: - 찾아보기 표식 (`hp:indexmark` → `idxm`)

    /// ctrl id + 키워드 1(길이 WORD + WCHAR 배열) + 키워드 2(같은 꼴) + UINT32.
    /// 마지막 UINT32는 위 실측대로 -1을 세운다 (레거시 저작기는 0).
    ///
    /// 키워드는 속성이 아니라 자식 요소의 텍스트다 (`hp:firstKey`·`hp:secondKey`,
    /// 한컴 공개 모델 `indexmark.cpp`는 속성을 하나도 읽지 않는다).
    private static func indexmark(
        _ node: HwpxXMLNode,
        context: HwpxMappingContext
    ) throws -> HwpOtherControl? {
        let keys = ["firstKey", "secondKey"]
        var units: [[UInt16]] = []
        for key in keys {
            guard let keyUnits = wcharUnits(
                node.paragraphFirstChild(named: key)?.text ?? ""
            ) else {
                return nil
            }
            units.append(keyUnits)
        }

        var payload = Data(capacity: 12 + units.reduce(0) { $0 + $1.count * 2 })
        payload.appendHwpxLittleEndian(HwpOtherCtrlId.indexmark.rawValue)
        for keyUnits in units {
            payload.appendHwpxLittleEndian(WORD(keyUnits.count))
            for unit in keyUnits {
                payload.appendHwpxLittleEndian(unit)
            }
        }
        payload.appendHwpxLittleEndian(UInt32.max)
        return try loaded(payload, node: node, consumed: keys, context: context)
    }

    // MARK: - 공통

    /// 합성 payload를 **바이너리 로더에 그대로 태운다** — typed 뷰와 로드 옵션
    /// 게이트를 한 번에 얻는 규약이다(#167·#168과 같다). `HwpOtherControl.init`은
    /// `rawTrailing`·`rawPayload`만 뷰어 게이트에 걸고 typed 뷰는 **게이트 전
    /// 원본**에서 만들므로, 필드를 직접 세우면 `.viewer`에서만 값이 사라지는
    /// 비대칭이 생긴다.
    private static func loaded(
        _ payload: Data,
        node: HwpxXMLNode,
        consumed: [String],
        context: HwpxMappingContext,
        children: [HwpRecord] = []
    ) throws -> HwpOtherControl {
        var reader = DataReader(payload, options: context.options)
        var control = try HwpOtherControl(&reader, children)
        control.unknownChildren = node.unconsumedChildRecords(
            consumed: Set(consumed), in: HwpxNamespace.paragraph,
            maxDepth: context.unknownDepthLimit
        )
        control.unknownChildren += node.duplicateSingletonRecords(
            of: consumed, in: HwpxNamespace.paragraph,
            maxDepth: context.unknownDepthLimit
        )
        return control
    }

    /// 길이 WORD에 담기는 UTF-16 배열. 65,535 단위를 넘으면 nil이다 —
    /// `WORD(count)`가 **트랩**하고(P1), 길이만 접으면 길이 필드와 바이트가
    /// 어긋나 `indexmarkInfo`가 잘린 문자열 + 나머지를 `rawTrailing`으로 읽는다.
    /// 잘라 맞추면 서러게이트 쌍이 갈리므로 통째로 강등한다.
    static func wcharUnits(_ text: String) -> [UInt16]? {
        let units = Array(text.utf16)
        return units.count <= Int(WORD.max) ? units : nil
    }
}

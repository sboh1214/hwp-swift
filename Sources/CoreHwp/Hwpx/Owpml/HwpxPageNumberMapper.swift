import Foundation

/// `hp:pageNum`(쪽 번호 위치)을 `.pageNumberPosition(HwpPageNumberPosition)`으로
/// 옮긴다 — 구역 부속 컨트롤(제어 문자 코드 21) 중 첫 typed 승격이다 (#135).
///
/// 조판(`HwpPageChromeBuilder`)은 typed 필드(`propertyInfo.displayPosition`·
/// `numberFormat`·앞/뒤 장식 문자·`unused`)만 읽으므로 payload는 렌더 필수가
/// 아니다. `.default`에서는 표 147의 16바이트(4CC + 속성 UINT32 + WCHAR×4)를
/// 합성해 바이너리 파싱 결과와 같은 모양을 유지하고(noori 쌍의 HWP manifest와
/// 바이트 동일), `.viewer`에서는 바이너리 경로(`DataReader.consumedData`)와 같이
/// `preservedPayload` 게이트로 비운다 — 진단 walker는 `unknownChildren`만 읽어
/// 양 모드 진단이 같다. `HwpxPictureMapper`의 73바이트는 렌더가
/// `pictureProperty`로 재디코딩하는 decoupled 부류라 게이트 대상이 아니다.
///
/// 생략 속성은 OWPML(ParaList 스키마) `default` 선언을 따른다 — `pos`
/// TOP_LEFT·`formatType` DIGIT·`sideChar` "-". 한글.app 실저장본은 세 속성을
/// 항상 명시하므로 이 경로는 제3자 저장기용이고, 한글.app이 `<hp:pageNum/>`을
/// 실제로 어떻게 그리는지는 실물이 없어 미검증이다. 미지 이름은 기본값으로
/// 접지 않고 0(위치 없음·숫자)으로 둔다 — 위치를 추측해 그리지 않는다.
///
/// 실측 근거 (`Sources/CoreHwp/Hwpx/AGENTS.md` "쪽 번호 위치"): noori 변환 쌍
/// (`BOTTOM_CENTER`↔5·`DIGIT`↔0·`sideChar=""`↔4번째 WCHAR 0, HWP 쌍 manifest
/// `pageNumberPositions[0]`과 바이트 동일)과 2026-09-02 한글.app 12.30.0 쪽 번호
/// 매기기 대화상자로 만든 .hwp/.hwpx 쌍 4종(`pos` 4값·`formatType` 4값·줄표
/// 유무). 실측된 값이 전부 스키마 나열 순서 = 표 148·표 134 코드였으므로
/// 미실측 값도 같은 규칙으로 채웠다.
enum HwpxPageNumberMapper {
    /// 제어 문자 코드 21(쪽 번호 위치) 앵커 + typed 컨트롤 — `classify`의 분기.
    static func anchor(
        _ node: HwpxXMLNode, context: HwpxMappingContext
    ) -> HwpxRunChildAction {
        .anchor(
            code: 21,
            fourCC: HwpOtherCtrlId.pageNumberPosition.rawValue,
            ctrl: .pageNumberPosition(map(node, context: context))
        )
    }

    static func map(
        _ node: HwpxXMLNode, context: HwpxMappingContext
    ) -> HwpPageNumberPosition {
        // 생략 → 스키마 기본값 TOP_LEFT(1), 미지 이름 → 0(위치 없음, 미렌더).
        let displayPosition = positions[node.attribute("pos") ?? "TOP_LEFT"] ?? 0
        // 생략 → DIGIT(0), 미지 이름 → 0 (HwpxNumberFormatMapper).
        let numberFormat = HwpxNumberFormatMapper.code(for: node.attribute("formatType"))
        // sideChar는 표 147 4번째 WCHAR(줄표 문자, #138)에 대응한다. 생략은 스키마
        // 기본값 "-"(0x2D), 명시 빈 문자열은 0(줄표 없음 — noori 실물), 두 글자
        // 이상이면 첫 UTF-16 unit(필드가 WCHAR 하나다). 앞/뒤 장식 문자는 HWPX에
        // 대응 속성이 없어 0으로 둔다 — 헌법주석 실물도 줄표를 장식이 아니라 이
        // 필드로 싣는다.
        let sideChar: WCHAR = (node.attribute("sideChar") ?? "-").utf16.first ?? 0

        // 표현이 셋이다 — property·propertyInfo 필드·propertyInfo.rawValue.
        // 바이너리는 load(property)가 셋을 함께 세우므로 여기서도 맞춘다.
        var propertyInfo = HwpPageNumberPositionProperty()
        propertyInfo.numberFormat = numberFormat
        propertyInfo.displayPosition = displayPosition
        propertyInfo.rawValue = UInt32(numberFormat & 0xFF)
            | (UInt32(displayPosition & 0xF) << 8)

        var payload = Data(capacity: 16)
        payload.appendHwpxLittleEndian(HwpOtherCtrlId.pageNumberPosition.rawValue)
        payload.appendHwpxLittleEndian(propertyInfo.rawValue)
        payload.appendHwpxLittleEndian(WCHAR(0)) // 사용자 기호
        payload.appendHwpxLittleEndian(WCHAR(0)) // 앞 장식 문자
        payload.appendHwpxLittleEndian(WCHAR(0)) // 뒤 장식 문자
        payload.appendHwpxLittleEndian(sideChar) // 줄표 문자 (공개 문서 '항상 "-"')

        return HwpPageNumberPosition(
            otherCtrlId: .pageNumberPosition,
            property: propertyInfo.rawValue,
            propertyInfo: propertyInfo,
            userSymbol: 0,
            headDecoration: 0,
            tailDecoration: 0,
            unused: sideChar,
            unknown: 0,
            // 보존 전용 슬라이스 — 바이너리 pgnp가 `.viewer`에서 비워지는 것과
            // 같은 게이트를 지난다 (HwpxPreviewMapper의 합성 payload와 같은 규약).
            rawPayload: context.options.preservedPayload(payload),
            rawTrailing: Data(),
            // 속성만 읽는 잎 요소다 — 자식이 오면 전부 미소비라 진단으로
            // 강등해야 "미해석 강등은 진단으로 보고됨" 규약이 지켜진다.
            unknownChildren: node.unconsumedChildRecords(
                consumed: [], maxDepth: context.unknownDepthLimit
            )
        )
    }

    /// OWPML `pos` → 표 148 bit 8-11 표시 위치 코드. 0 없음, 1~3 위(왼/가운데/
    /// 오른), 4~6 아래(왼/가운데/오른), 7/8 바깥쪽 위/아래, 9/10 안쪽 위/아래 —
    /// `HwpPageChromeBuilder.pageNumberPlacement`가 소비하는 코드다.
    static let positions: [String: Int] = [
        "NONE": 0,
        "TOP_LEFT": 1,
        "TOP_CENTER": 2,
        "TOP_RIGHT": 3,
        "BOTTOM_LEFT": 4,
        "BOTTOM_CENTER": 5,
        "BOTTOM_RIGHT": 6,
        "OUTSIDE_TOP": 7,
        "OUTSIDE_BOTTOM": 8,
        "INSIDE_TOP": 9,
        "INSIDE_BOTTOM": 10,
    ]
}

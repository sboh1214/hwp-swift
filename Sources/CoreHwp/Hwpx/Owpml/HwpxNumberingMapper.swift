import Foundation

/// 표 39 문단 머리 정보 — `hh:numbering`과 `hh:bullet`이 공유하는
/// `hh:paraHead` 하나의 12바이트다.
///
/// 스펙은 항목 4개(속성 `UINT32` · 너비 보정값 `HWPUNIT16` · 본문과의 거리
/// `HWPUNIT16` · 글자 모양 아이디 참조 `INT32`)를 적고 "전체 길이 8"로 합계를
/// 틀리게 적었다 — 실물은 12바이트다 (`HwpBullet` 파싱 주석의 noori `-` 실측).
/// `HwpNumberingFormat.property`는 12바이트를 통째로 들고, `HwpBullet`은 같은
/// 12바이트를 `info`(앞 8바이트)와 `headCharShapeId`로 쪼개 든다.
struct HwpxParaHeadInfo {
    /// 표 40 문단 머리 정보 속성.
    var property: UInt32 = 0
    var widthAdjust: HWPUNIT16 = 0
    var textOffset: HWPUNIT16 = 0
    /// 문단 머리 글자 모양 ID — -1이면 바탕글 모양이다.
    var charShapeId: Int32 = -1

    /// `HwpBullet.info`가 드는 앞 8바이트.
    var infoBytes: [BYTE] {
        var data = Data(capacity: 8)
        data.appendHwpxLittleEndian(property)
        data.appendHwpxLittleEndian(UInt16(bitPattern: widthAdjust))
        data.appendHwpxLittleEndian(UInt16(bitPattern: textOffset))
        return Array(data)
    }

    /// `HwpNumberingFormat.property`가 드는 12바이트 전체.
    var propertyBytes: [BYTE] {
        var data = Data(capacity: 12)
        data.append(contentsOf: infoBytes)
        data.appendHwpxLittleEndian(UInt32(bitPattern: charShapeId))
        return Array(data)
    }
}

/// `hh:numberings`·`hh:bullets` 가족을 문단 번호·글머리표 정의로 옮긴다 (#133).
///
/// 참조 배선은 이 승격 전부터 끝나 있었다 — `HwpxParaShapeMapper`가
/// `hh:paraPr`의 `hh:heading`을 표 44 문단 머리 종류·수준과 1-based
/// `numberingOrBulletId`로 이미 옮긴다. 비어 있던 것은 정의 배열뿐이라,
/// 조판은 `numberingOrBulletId > 0` 게이트를 지나고도 `HwpIndex`에서 정의를
/// 찾지 못해 아무것도 그리지 않았다.
///
/// 조판이 실제로 읽는 것은 `HwpBullet.char` 하나다
/// (`HwpTextRunBuilder.appendBulletHeading`이 `char + " "`를 문단 앞에 전치).
/// 번호 문단 머리의 라벨(`^1.` 캐럿 서식 파서·자동 번호 카운터·수준 승계)은
/// HWP 경로에도 없어 `numberingArray` 승격의 성과는 모델·등가·진단까지다.
///
/// 표 40 속성 비트는 저장소 안에서 확정된다. 빈 문서 기본 `numberingArray`
/// (`HwpIdMappings`)의 수준별 속성 선두 `UINT32`가 `^1.` 0x0C · `^2.` 0x10C ·
/// `^7` 0x2C이고, noori HWPX의 같은 수준이 `numFormat="DIGIT"`(표 41 값 0)·
/// `"HANGUL_SYLLABLE"`(8)·`"CIRCLED_DIGIT"`(1)이라 bit 5-8이 표 41 코드다.
/// 0x0C와 수준 8-10 기본값 0x08의 차이가 bit 2 = `useInstWidth`, 두 값 모두
/// 선 bit 3 = `autoIndent`다. 정렬(bit 0-1)과 거리 종류(bit 4)는 픽스처 10종에
/// 비-기본값 사례가 없어 스키마 나열 순서로 채우고 실파일 검증 대기 항목에
/// 남긴다 (`Sources/CoreHwp/Hwpx/AGENTS.md`).
enum HwpxNumberingMapper {
    /// 표 38이 7회 반복하는 수준(1-7) — `HwpNumbering.formatArray`.
    static let documentedLevelCount = 7
    /// 표 38이 3회 반복하는 확장 수준(8-10) — `extendedFormatArray`.
    static let extendedLevelCount = 3

    /// `hh:numbering` 하나 → `HwpNumbering`.
    static func mapNumbering(
        _ node: HwpxXMLNode, tables: HwpxIdTables
    ) -> HwpxNumberingDefinition {
        let assignment = assignLevels(node)
        let levels = (1 ... documentedLevelCount + extendedLevelCount).map {
            assignment.slots[$0]
        }
        let formats = levels.map { format(for: $0, tables: tables) }
        // 수준별 시작 번호는 표 38이 UINT(4바이트)로 적고 한컴 모델도 `UINT`다
        // (`CParaHeadType2::m_StartNumber`). `uint16Attribute`로 먼저 읽으면
        // 65,535를 넘는 값이 파싱 실패로 기본값 1이 되어 조용히 뭉개진다 —
        // 문서 수준 `hh:numbering@start`만 표 38대로 UINT16이다.
        let startingIndexes = levels.map { $0?.uint32Attribute("start", default: 1) ?? 1 }

        return HwpxNumberingDefinition(
            numbering: HwpNumbering(
                formatArray: Array(formats.prefix(documentedLevelCount)),
                startingIndex: node.uint16Attribute("start", default: 1),
                startingIndexArray: Array(startingIndexes.prefix(documentedLevelCount)),
                extendedFormatArray: Array(formats.suffix(extendedLevelCount)),
                extendedStartingIndexArray: Array(startingIndexes.suffix(extendedLevelCount))
            ),
            rejectedParaHeadIndices: assignment.rejected
        )
    }

    /// `hh:bullet` 하나 → `HwpBullet`.
    ///
    /// 글머리표의 `hh:paraHead`는 수준 슬롯이 아니라 하나뿐이다 (noori 실물은
    /// `level="0"`) — 첫 등장만 소비하고 나머지는 진단으로 강등한다.
    static func mapBullet(
        _ node: HwpxXMLNode, tables: HwpxIdTables
    ) -> HwpxBulletDefinition {
        let paraHeads = node.headChildren(named: "paraHead")
        return HwpxBulletDefinition(
            bullet: bullet(paraHeads.first, of: node, tables: tables),
            rejectedParaHeadIndices: Array(paraHeads.indices.dropFirst())
        )
    }

    /// `hh:paraHead` 하나 → 표 39 문단 머리 정보.
    ///
    /// 생략 속성은 OWPML 스키마의 `default`를 따른다 — 한글.app 실저장본은
    /// 열한 속성을 모두 명시해 생략 경로의 실물이 없다. 표 39·표 40에 대응
    /// 필드가 없는 `checkable`은 싣지 않는다.
    static func paraHeadInfo(
        _ node: HwpxXMLNode?, tables: HwpxIdTables
    ) -> HwpxParaHeadInfo {
        guard let node else {
            return HwpxParaHeadInfo()
        }
        var property = UInt32(alignments[node.attribute("align") ?? "LEFT"] ?? 0) & 0b11
        // 생략은 참이다. 근거는 생성자 초기값이 아니라 **참조 리더의 생략
        // 처리**다 — 한컴 `Util.cpp`의 `GetAttribute(..., bool& value)`는 속성이
        // 없으면 `value`를 건드리지 않고 false를 반환하므로, 생성자가 세운
        // `m_bUseInstWidth(true)`·`m_bAutoIndent(true)`(`ParaHeadType.cpp`)가
        // 그대로 남는다. 인자 없는 `boolAttribute`의 거짓 기본값을 쓰면 두 속성을
        // 생략하는 저장기의 문서에서 bit 2·3이 참조 구현과 반대로 선다.
        if node.boolAttribute("useInstWidth", default: true) {
            property |= 1 << 2
        }
        if node.boolAttribute("autoIndent", default: true) {
            property |= 1 << 3
        }
        if textOffsetTypes[node.attribute("textOffsetType") ?? "PERCENT"] ?? 0 != 0 {
            property |= 1 << 4
        }
        // 표 41 코드는 표 134 번호 모양의 0-14 구간과 항목이 같아
        // `HwpxNumberFormatMapper`를 재사용한다 — #135가 분리해 둔 표다.
        // bit 5-8은 4비트라 0-14만 담긴다 (`SYMBOL` 0x80 등은 표 41 밖이다).
        let numberFormat = HwpxNumberFormatMapper.code(for: node.attribute("numFormat"))
        property |= (UInt32(numberFormat) & 0b1111) << 5

        return HwpxParaHeadInfo(
            property: property,
            widthAdjust: HWPUNIT16(clamping: node.intAttribute("widthAdjust", default: 0)),
            textOffset: HWPUNIT16(clamping: node.intAttribute("textOffset", default: 50)),
            charShapeId: charShapeId(node.attribute("charPrIDRef"), tables: tables)
        )
    }

    /// 표 40 bit 0-1 문단의 정렬 종류.
    static let alignments: [String: Int] = ["LEFT": 0, "CENTER": 1, "RIGHT": 2]

    /// 표 40 bit 4 수준별 본문과의 거리 종류 — 0 글자 크기에 대한 상대 비율.
    static let textOffsetTypes: [String: Int] = ["PERCENT": 0, "HWPUNIT": 1]
}

/// `hh:numbering` 하나의 매핑 결과.
struct HwpxNumberingDefinition {
    var numbering: HwpNumbering
    /// 수준 슬롯을 얻지 못한 `hh:paraHead`의 문서 순서 인덱스 — 중복 수준의
    /// 두 번째 이후와 1-10 밖 수준이다. 호출자가 진단으로 강등한다.
    var rejectedParaHeadIndices: [Int]
}

/// `hh:bullet` 하나의 매핑 결과.
struct HwpxBulletDefinition {
    var bullet: HwpBullet
    /// 첫 등장 뒤에 온 `hh:paraHead`의 문서 순서 인덱스.
    var rejectedParaHeadIndices: [Int]
}

private extension HwpxNumberingMapper {
    static func bullet(
        _ paraHead: HwpxXMLNode?, of node: HwpxXMLNode, tables: HwpxIdTables
    ) -> HwpBullet {
        let info = paraHeadInfo(paraHead, tables: tables)
        return HwpBullet(
            hwpxInfo: info.infoBytes,
            headCharShapeId: info.charShapeId,
            char: wchar(node.attribute("char")),
            checkChar: wchar(node.attribute("checkedChar"))
        )
    }

    /// `hh:paraHead@level` → 수준 슬롯(1-10). 같은 수준이 두 번 오면 첫 등장이
    /// 이긴다 (가족 중복·아카이브 중복 엔트리와 같은 결정적 규칙).
    static func assignLevels(
        _ node: HwpxXMLNode
    ) -> (slots: [Int: HwpxXMLNode], rejected: [Int]) {
        var slots: [Int: HwpxXMLNode] = [:]
        var rejected: [Int] = []
        let levelRange = 1 ... documentedLevelCount + extendedLevelCount
        for (index, paraHead) in node.headChildren(named: "paraHead").enumerated() {
            let level = paraHead.intAttribute("level", default: 0)
            guard levelRange.contains(level), slots[level] == nil else {
                rejected.append(index)
                continue
            }
            slots[level] = paraHead
        }
        return (slots, rejected)
    }

    /// 수준 하나 → `HwpNumberingFormat`. 번호 형식 문자열은 속성이 아니라
    /// 요소 텍스트다. 슬롯이 빈 수준은 형식 길이 0·속성 0·바탕글(-1)이다.
    ///
    /// `formatLength == format.utf16.count`는 바이너리 파서가 보장하는 불변식이라
    /// (표 38이 WORD 길이 + WCHAR×len으로 적고 로더가 len개를 정확히 읽는다)
    /// 길이만 접히면 모델이 어긋난다. 여기 `clamping`은 방어용이고, 실제 거부는
    /// `HwpxHeaderMapper.mapNumberings`가 가족 단위로 먼저 한다 — 65,535 단위에서
    /// 자르는 절단은 서러게이트 쌍을 갈라 조용히 손상시키므로 쓰지 않는다.
    static func format(
        for node: HwpxXMLNode?, tables: HwpxIdTables
    ) -> HwpNumberingFormat {
        let format = node?.text ?? ""
        return HwpNumberingFormat(
            property: paraHeadInfo(node, tables: tables).propertyBytes,
            formatLength: WORD(clamping: format.utf16.count),
            format: format
        )
    }

    /// `charPrIDRef`는 id 테이블 참조지만 `4294967295`(-1)는 센티널이다 —
    /// 바탕글 모양을 뜻하므로 리맵하면 안 된다. 그대로 `resolvedOffset`에
    /// 넣으면 댕글링 폴백 0이 되어 charShape 0을 가리킨다.
    static func charShapeId(_ ref: String?, tables: HwpxIdTables) -> Int32 {
        guard let ref, UInt32(ref) != UInt32.max, ref != "-1" else {
            return -1
        }
        return Int32(clamping: tables.charShape.resolvedOffset(of: ref))
    }

    /// WCHAR 한 자 필드 — 빈 문자열·생략은 문자 없음(빈 문자열), 두 글자
    /// 이상은 첫 UTF-16 unit이다 (`hp:pageNum sideChar`와 같은 규약).
    /// 조판은 `char.isEmpty` 게이트로 글머리표를 건너뛰므로 U+0000 한 자로
    /// 접으면 NUL 글리프를 그리게 된다.
    static func wchar(_ value: String?) -> String {
        guard let unit = value?.utf16.first, unit != 0 else {
            return ""
        }
        return String(utf16CodeUnits: [unit], count: 1)
    }
}

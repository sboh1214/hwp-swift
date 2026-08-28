import Foundation

/// OWPML `id` 속성(문자열) → HWP5식 배열 오프셋 리맵 테이블 하나.
///
/// HWPX의 id는 dense가 아니다 (실측: borderFill은 1부터, charPr은 0부터).
/// `HwpIndex`는 배열 오프셋으로 키를 만들므로, 가족별로 **문서 등장 순서**의
/// 오프셋을 부여하고 모든 `*IDRef`를 매핑 시점에 이 테이블로 재작성한다 —
/// 결손 id를 빈 항목으로 메우는 gap-fill보다 안전하다 (id 공간이 희소해도
/// 배열이 부풀지 않고, 참조가 남김없이 재작성됨이 테이블에 드러난다).
struct HwpxIdTable {
    private var offsets: [String: UInt32] = [:]

    /// 같은 id의 중복 선언은 첫 등장이 이긴다 (아카이브 중복 엔트리와 동일한
    /// 결정적 규칙).
    mutating func register(id: String?, offset: Int) {
        guard let id, !id.isEmpty, offsets[id] == nil,
              let value = UInt32(exactly: offset)
        else {
            return
        }
        offsets[id] = value
    }

    func offset(of ref: String?) -> UInt32? {
        guard let ref else {
            return nil
        }
        return offsets[ref]
    }

    /// 댕글링 참조는 0으로 폴백한다 — 렌더 스택이 사전 조회 실패를 기본값으로
    /// 처리하므로 문서를 죽이지 않는 쪽이 맞다 (복구 모드와 같은 태도).
    func resolvedOffset(of ref: String?) -> UInt32 {
        offset(of: ref) ?? 0
    }
}

/// header.xml 한 문서의 가족별 리맵 테이블 모음.
struct HwpxIdTables {
    /// 언어 7종별 글꼴 id 공간 — `HwpIdMappings`의 7개 faceName 배열 순서
    /// (Korean/English/Chinese/Japanese/Etc/Symbol/User)와 같은 인덱스다.
    var fontFacesByLanguage: [HwpxIdTable] = Array(repeating: HwpxIdTable(), count: 7)
    var borderFill = HwpxIdTable()
    var charShape = HwpxIdTable()
    var tabDef = HwpxIdTable()
    var numbering = HwpxIdTable()
    var bullet = HwpxIdTable()
    var paraShape = HwpxIdTable()
    var style = HwpxIdTable()

    /// borderFill 참조만 1-based다 — 렌더 스택이 "0 = 없음, N = 배열
    /// 오프셋 N-1" 관례로 해석한다 (`HwpTableLayout.resolvedBorderFill`,
    /// 실물 HWPX도 id를 1부터 매긴다). 댕글링은 0(없음)으로 폴백한다.
    func borderFillId(of ref: String?) -> UInt16 {
        guard let offset = borderFill.offset(of: ref) else {
            return 0
        }
        return UInt16(clamping: offset + 1)
    }
}

/// OWPML `hh:fontface lang` → `HwpIdMappings` faceName 배열 인덱스.
enum HwpxFontLanguage: String, CaseIterable {
    case hangul = "HANGUL"
    case latin = "LATIN"
    case hanja = "HANJA"
    case japanese = "JAPANESE"
    case other = "OTHER"
    case symbol = "SYMBOL"
    case user = "USER"

    /// HWP5 글자 모양의 언어 배열 순서 (한글/영어/한자/일어/기타/기호/사용자).
    var arrayIndex: Int {
        switch self {
        case .hangul: 0
        case .latin: 1
        case .hanja: 2
        case .japanese: 3
        case .other: 4
        case .symbol: 5
        case .user: 6
        }
    }
}

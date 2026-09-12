import Foundation

/// OWPML `LINETYPE2` 이름 → HWP5 선 종류 값.
///
/// 한컴 공개 모델은 밑줄·취소선(`hh:underline@shape`·`hh:strikeout@shape`), 테두리/배경의
/// 네 방향·대각선(`hh:borderFill`), 각주·미주 구분선(`hp:noteLine@type`), 단 구분선
/// (`hp:colLine@type`)에 같은 이름표(`OWPML/Class/enumdef.h`의 `g_LineTypeList2`)를
/// 쓰지만, HWP5 바이너리는 **자리마다 값의 기준이 다르다** (#177, 2026-09-12 한글
/// 12.30.0으로 저장한 `line-shapes` 쌍 실측):
///
/// - 글자 모양 밑줄·취소선 모양(표 35 bit 4-7·26-29 → 표 25): **`LINETYPE2 - 1`** —
///   SOLID 0 · DOT 1 · DASH 2 · … · 3D 15. 4비트 필드라 REV3D(16)는 담기지 않고 한글이
///   SOLID(0)로 접는다.
/// - 테두리·대각선·각주/미주 구분선·단 구분선: **`LINETYPE2` 그대로** — NONE 0 · SOLID 1 ·
///   DOT 2 · DASH 3 · … · REV3D 17 (`HwpBorderType`의 raw 값과 같은 축).
///
/// **이름과 모양이 어긋난다** — 한글은 `DOT`(글자선 1 · 테두리 2)를 **긴 점선(파선)**으로,
/// `DASH`(글자선 2 · 테두리 3)를 **점선**으로 그린다(같은 문서의 PDF 내보내기 실측).
/// 스펙 표 25의 "1 긴 점선 · 2 점선"과 값은 같고 OWPML 이름만 뒤바뀐 것이므로, 이 표는
/// 이름의 뜻이 아니라 **열거 순서(값)** 를 따른다. 종전 표는 이름의 뜻을 따라
/// `DASH`↔2·`DOT`↔3으로 두었고 글자선에도 테두리 값을 그대로 실어 실선이 1로 파싱됐다.
///
/// 3D 넷의 이름은 `THICK3D`·`THICKREV3D`·`3D`·`REV3D`다 — 밑줄 표기(`THICK_3D` 등)를
/// 지어내 쓰면 실물 문서의 3D 선이 조용히 기본값이 된다. 글자 외곽선(`hh:outline@type`)만은
/// 다른 열거(`LINETYPE1`)라 `HwpxCharShapeMapper.outlineTypes`가 따로 있다.
enum HwpxLineTypeMapper {
    /// 테두리·구분선 계열 — `LINETYPE2` 값 그대로 (`HwpBorderType` raw와 같다).
    static let borderLineTypes: [String: Int] = [
        "NONE": 0, "SOLID": 1, "DOT": 2, "DASH": 3, "DASH_DOT": 4,
        "DASH_DOT_DOT": 5, "LONG_DASH": 6, "CIRCLE": 7, "DOUBLE_SLIM": 8,
        "SLIM_THICK": 9, "THICK_SLIM": 10, "SLIM_THICK_SLIM": 11,
        "WAVE": 12, "DOUBLEWAVE": 13, "THICK3D": 14,
        "THICKREV3D": 15, "3D": 16, "REV3D": 17,
    ]

    /// 글자 모양 밑줄·취소선 모양 — 표 25 값(실선 0). `NONE`은 이 자리에 값이 없고
    /// (한글은 밑줄 없는 글자 모양에도 `shape="SOLID"`를 적는다) `REV3D`는 4비트를
    /// 넘쳐 한글이 SOLID로 접으므로 둘 다 0이다 — `characterLineShape`의 기본값이 맡는다.
    static let characterLineShapes: [String: Int] = [
        "SOLID": 0, "DOT": 1, "DASH": 2, "DASH_DOT": 3,
        "DASH_DOT_DOT": 4, "LONG_DASH": 5, "CIRCLE": 6, "DOUBLE_SLIM": 7,
        "SLIM_THICK": 8, "THICK_SLIM": 9, "SLIM_THICK_SLIM": 10,
        "WAVE": 11, "DOUBLEWAVE": 12, "THICK3D": 13,
        "THICKREV3D": 14, "3D": 15,
    ]

    /// 테두리·대각선·각주/미주 구분선·단 구분선의 종류. 생략·미지 이름은 호출부가 넘긴
    /// 기본값으로 접는다 (한컴 `GetAttribute` 규약 — 생성자 값이 남는다).
    static func borderLineType(_ name: String?, default defaultValue: Int) -> Int {
        guard let name else {
            return defaultValue
        }
        return borderLineTypes[name] ?? defaultValue
    }

    /// 글자 모양 밑줄·취소선 모양. 생략·`NONE`·`REV3D`·미지 이름은 실선(0)이다.
    static func characterLineShape(_ name: String?) -> Int {
        guard let name else {
            return 0
        }
        return characterLineShapes[name] ?? 0
    }
}

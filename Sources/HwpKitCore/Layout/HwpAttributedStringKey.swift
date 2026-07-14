import Foundation

public enum HwpAttributedStringKey {
    public static let underlineColor = NSAttributedString.Key("hwp.underlineColor")
    /// extended 컨트롤 문자(U+FFFC)가 가리키는 ctrlHeaderArray index (NSNumber).
    /// k번째 extended 컨트롤 문자 ↔ k번째 컨트롤 헤더 (noori/header-footer 픽스처 검증).
    public static let controlIndex = NSAttributedString.Key("hwp.controlIndex")
    /// 음영 색 (CGColor) — run 배경 칠하기
    public static let shadeColor = NSAttributedString.Key("hwp.shadeColor")
    /// 그림자 색 (CGColor) + 오프셋 (pt, NSNumber) — run 글리프 그림자
    public static let shadowColor = NSAttributedString.Key("hwp.shadowColor")
    public static let shadowOffsetX = NSAttributedString.Key("hwp.shadowOffsetX")
    public static let shadowOffsetY = NSAttributedString.Key("hwp.shadowOffsetY")
    /// 취소선 색 (CGColor)
    public static let strikethroughColor = NSAttributedString.Key("hwp.strikethroughColor")
    /// 취소선 여부 — NSStrikethrough 키를 쓰면 CTLineDraw가 자체로 한 번 더
    /// 그려 이중선이 된다 (CharShape 실물 대조 2026-07-10)
    public static let strikethroughStyle = NSAttributedString.Key("hwp.strikethroughStyle")
    /// 양각/음각 (NSNumber: 1 양각, 2 음각) — 밝은/어두운 오프셋 사본 3-pass
    public static let reliefStyle = NSAttributedString.Key("hwp.reliefStyle")
    /// 양각/음각 run의 실제 글자색 (CGColor) — 글리프 자체는
    /// kCTForegroundColorFromContext로 그려서 사본 색을 컨텍스트로 바꾼다
    public static let reliefFaceColor = NSAttributedString.Key("hwp.reliefFaceColor")
    /// 강조점 (NSNumber != 0) — 글리프 위 가운데 점
    public static let emphasisMark = NSAttributedString.Key("hwp.emphasisMark")
    /// 글자 위치 (표 33 location) — 줄 안 세로 오프셋 (pt, 양수 = 위).
    /// kCTBaselineOffset은 CTFramesetter가 무시하므로 직접 그린다.
    public static let glyphBaselineOffset = NSAttributedString.Key("hwp.glyphBaselineOffset")
    /// 밑줄 여부 — CT 밑줄 대신 렌더러가 0.4pt 헤어라인으로 직접 그린다
    public static let underlineStyle = NSAttributedString.Key("hwp.underlineStyle")
    /// 상대크기 적용 전 기본 글자 크기 (pt) — % 줄 간격의 기준
    public static let baseFontSize = NSAttributedString.Key("hwp.baseFontSize")
    /// 고정 공백 폭 (0.5em)의 기준 크기 — 상대크기는 반영, 첨자 축소는
    /// 제외한 글자 크기 (라운드 12 실측: 상대크기 170 줄 공백도 1.7배)
    public static let spaceTargetSize = NSAttributedString.Key("hwp.spaceTargetSize")
    /// 문단이 다음 단/쪽으로 이어지는 조각의 마지막 문자 마커 — 이 조각의
    /// 끝 줄은 문단 마지막 줄이 아니므로 양쪽 정렬을 유지한다
    public static let continuedParagraphFragment =
        NSAttributedString.Key("hwp.continuedParagraphFragment")

    /// 페이지에 걸친 표의 반복된 제목 행 클론 표식 — 렌더·선택에는 남지만
    /// 복사 소스 텍스트에는 한 번만 포함한다 (페이지마다 중복 방지).
    public static let repeatedTableHeaderClone =
        NSAttributedString.Key("hwp.repeatedTableHeaderClone")
    /// 탭 채움 종류 (HwpTabInfo.fillType != 0) — 렌더러가 탭 전진 구간에
    /// 점선 리더를 그린다 (목차 실물)
    public static let tabLeader = NSAttributedString.Key("hwp.tabLeader")
    /// 연속 그림자 — 본체에서 오프셋까지 이어지는 두꺼운 그림자
    public static let shadowContinuous = NSAttributedString.Key("hwp.shadowContinuous")
    /// 변경 추적 삽입 밑줄 — 한글은 베이스라인 아래 ~0.22em에 그린다
    public static let trackInsertUnderline = NSAttributedString.Key("hwp.trackInsertUnderline")
    /// 메모 앵커 둥근 테두리 색 (연녹 채움 위 괄호형 외곽선)
    public static let memoAnchorStroke = NSAttributedString.Key("hwp.memoAnchorStroke")
    /// 배분/나눔 정렬 (표 44 정렬 4·5) — 마지막 줄도 단어 간격을 벌린다
    public static let distributeAlignment = NSAttributedString.Key("hwp.distributeAlignment")
}

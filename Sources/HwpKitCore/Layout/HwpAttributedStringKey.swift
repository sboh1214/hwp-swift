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
    /// 변경 추적 삭제선 표식 (NSNumber != 0) — 같은 취소선 경로로 그리되 한글이
    /// 변경 추적 표시에만 쓰는 다른 높이
    /// (`HwpRenderTuning.Text.trackChangeStrikethroughCenterRatio`)를 쓴다 (#136)
    public static let trackChangeStrikethrough =
        NSAttributedString.Key("hwp.trackChangeStrikethrough")
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
    /// 밑줄 여부 (글자 아래) — CT 밑줄 대신 렌더러가 0.4pt 헤어라인으로 직접 그린다
    public static let underlineStyle = NSAttributedString.Key("hwp.underlineStyle")
    /// 밑줄 '글자 위' 여부 (표 35 밑줄 종류 3) — 같은 헤어라인을 베이스라인
    /// **위** `underlineAboveCenterRatio`에 그린다 (#136). 색은
    /// `underlineColor`를 공유한다.
    public static let underlineAboveStyle = NSAttributedString.Key("hwp.underlineAboveStyle")
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
    /// 탭 stop 목록 (위치pt·fillType 교대) — draw가 각 탭이 겨냥한 stop의
    /// 채움을 위치로 판정한다 (#4)
    public static let tabLeaderStops = NSAttributedString.Key("hwp.tabLeaderStops")
    /// 연속 그림자 — 본체에서 오프셋까지 이어지는 두꺼운 그림자
    public static let shadowContinuous = NSAttributedString.Key("hwp.shadowContinuous")
    /// 변경 추적 삽입 밑줄 — 한글은 베이스라인 아래 ~0.22em에 그린다
    public static let trackInsertUnderline = NSAttributedString.Key("hwp.trackInsertUnderline")
    /// 메모 앵커 둥근 테두리 색 (연녹 채움 위 괄호형 외곽선)
    public static let memoAnchorStroke = NSAttributedString.Key("hwp.memoAnchorStroke")
    /// 배분/나눔 정렬 (표 44 정렬 4·5) — 마지막 줄도 단어 간격을 벌린다
    public static let distributeAlignment = NSAttributedString.Key("hwp.distributeAlignment")
    /// 하이퍼링크(%hlk) 필드가 감싸는 텍스트의 URL — 히트/페인트가 블록 전체가
    /// 아니라 이 속성 범위의 글리프 rect로 링크를 스코프한다 (#2).
    public static let hyperlink = NSAttributedString.Key("hwp.hyperlink")
    /// **조판 전용 앵커** 표식 — 한 줄 끝(10)으로 끝난 문단의 마지막 빈 줄을
    /// 살리는 빈칸(`HwpTextRunBuilder.emittedText`, #137)과, 글자가 없는 문단의
    /// 조판 문자열인 빈 문단 앵커(`emptyParagraphAnchor`, #145)가 같은 표식을 쓴다.
    /// 문자 자체는 빈칸이라 사용자가 입력한 공백과 구별되지 않으므로, 장식
    /// 제거·복사 제외·검색 제외는 이 표식으로만 판정한다.
    public static let emptyLineAnchor = NSAttributedString.Key("hwp.emptyLineAnchor")
    /// 문단 번호·개요 번호 **라벨** 표식 (NSNumber true, #154) —
    /// `HwpTextRunBuilder.appendNumberingHeading`이 문단 앞에 전치한 라벨 글자와
    /// 번호 너비 여백·본문과의 거리를 내는 빈칸에 붙는다. 라벨은 PARA_TEXT에 없는
    /// 생성 문자열이라 원본 WCHAR 위치가 없다 — 복사 텍스트에는 넣고(한글.app
    /// 실측: 자동 번호 라벨도 복사된다) 라벨을 가려야 하는 소비자는 이 표식으로
    /// 판정한다.
    public static let numberingLabel = NSAttributedString.Key("hwp.numberingLabel")
    /// 라벨의 자동 내어쓰기 전진량 (pt, NSNumber, #154) — 라벨 폭 + 번호 너비의
    /// 뒤 여백 + 본문과의 거리(앞 여백은 `numberingFirstLineInset`이 첫 줄 들여쓰기로
    /// 낸다). 문단 머리 정보의 `autoIndent`가 켜진 라벨 범위에만 붙고
    /// `HwpParagraphLayout.ParagraphMetrics`가 둘째 줄부터의 `headIndent`에 더한다.
    public static let numberingHeadIndent = NSAttributedString.Key("hwp.numberingHeadIndent")
    /// 라벨 앞의 번호 너비 여백 (pt, NSNumber, #154) — 가운데·오른쪽 정렬로 번호 너비
    /// 안에서 라벨이 밀려난 폭. 글자를 넣지 않고 첫 줄 들여쓰기(`firstLineHeadIndent`)로
    /// 낸다 — 앞에 빈칸을 넣으면 복사 텍스트가 빈칸으로 시작해 한글.app과 달라진다.
    public static let numberingFirstLineInset = NSAttributedString.Key("hwp.numberingFirstLineInset")
}

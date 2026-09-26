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
    /// 호환 문서의 대상 프로그램 (표 55, NSNumber = `HwpCompatibleDocumentTarget.rawValue`,
    /// #187·#210) — 조판(`HwpTextRunBuilder.attributes(for:script:)`)이 한글 문서가 아닌
    /// 문서의 **모든 run**에 싣는다 (한글 문서·record 없음·미지 raw 값은 키 없음).
    /// 렌더러(`HwpPageLayerDecorations`)는 `msWord`에서 밑줄·취소선·변경 추적 표시선을
    /// 글꼴 지표 기하(`HwpDecorationLineGeometry`)로, `hwp200X`에서 글자 크기 비례 자리의
    /// 고정 0.36pt 선으로 그리고 (`isHwp2007Compatible`), 나머지 값은 한글 문서와 같이
    /// 글자 크기 비례 0.04em 선으로 그린다. 세로 배치
    /// (`HwpDrawnTextLayout.LineMetrics`, #194)는 **`msWord`에서만** 줄 상자·베이스라인·
    /// 전진량을 글꼴 줄 상자(`HwpMsWordLineBox`)로 잡는다 — `hwp200X`의 줄 상자는 한글
    /// 문서와 같다 (장식선만 갈린다). CoreText가 대체 글꼴로 쪼갠 run에도 그대로 남으므로 대체 글꼴 run의 선·상자도
    /// 같은 갈래를 탄다.
    public static let compatibleDocumentTarget =
        NSAttributedString.Key("hwp.compatibleDocumentTarget")
    /// MS 워드 호환 문서의 **문단 끝 글자** 줄 상자 (`[NSNumber]` = [줄 상자 높이 pt,
    /// 상자 상단 → 베이스라인 pt], #187) — 조판(`HwpTextRunBuilder.finishBuild`)이 문단
    /// 조판 문자열 **전체**에 싣는다 (마지막 글자 하나에만 얹으면 속성 경계가 이모지
    /// 서로게이트 쌍·결합 문자·합자의 글리프 조합을 가르고, 마지막 속성 run에만 얹어도
    /// 글자 모양 id만 다른 합자 `لا`·결합 문자에서 CoreText가 앞 run의 속성만 남겨 상자를
    /// 버린다 — PR 리뷰). 한글은 문단 끝 글자(CR)를 마지막 글자 모양의 **라틴 슬롯** 글꼴로
    /// 그 줄에 세우므로, 조판 문자열에서 접힌 CR의 상자를 렌더러가 **문단의 마지막 줄**
    /// (`HwpDrawnLine.endsParagraph` — 이어짐 표식이 없는 조각의 끝 줄, 결합 문자열 안에서는
    /// 한 줄 끝 표식이 아닌 문단 구분자로 끝나는 줄)의 줄 상자
    /// (`HwpMsWordLineBox.union`)에 되돌려 넣는다 (한글 실측: Apple SD 20pt 한글
    /// 문단의 마지막 줄만 Menlo 라틴 슬롯의 베이스라인 2207을 받아 밑줄이 −0.2994em으로
    /// 올라간다; 앞 줄들은 −0.3234em). 밑줄과 세로 배치(#194 — 마지막 줄의 베이스라인
    /// 앵커·상자 높이)가 이 상자를 보고 취소선은 run 단위라 보지 않는다.
    public static let msWordParagraphEndBox =
        NSAttributedString.Key("hwp.msWordParagraphEndBox")
    /// **문단 끝 글자**(CR, 코드 13)의 상대크기 적용 전 기본 글자 크기 (NSNumber pt, #206) —
    /// 조판(`HwpTextRunBuilder.finishBuild`)이 잘리지 않은 문단의 조판 문자열 **전체**에
    /// 싣는다 (`msWordParagraphEndBox`와 같은 이유로 마지막 글자 하나에 얹지 않는다). CR은
    /// 조판 문자열에서 접히지만(`controlText`, #137) 한글은 그 글자의 글자 모양도 문단
    /// **마지막 줄**의 글자 상자에 넣는다 — 줄 상자(`vertsize`)와 비율 줄 간격 여분의 기준
    /// 둘 다다 (한글 12.30 실측 2026-09-21: 함초롬바탕 10pt 본문 + 16pt CR 문단의 마지막
    /// 줄만 `vertsize` 1600·`baseline` 1360·160% `spacing` 960이고 앞 줄들은 1000·850·600;
    /// `noori` 2번째 문단은 표 마커 10pt + CR 16pt 줄의 `spacing`이 1120 = 16 × 0.7).
    /// 한 줄 끝(코드 10)으로 나뉜 앞 줄에는 들지 않는다 — 그 줄은 한 줄 끝 글자 자신의
    /// 글자 모양을 싣는다(`hwp.lineBreak` run의 `baseFontSize`). 어느 줄이 마지막 줄인지는
    /// `HwpDrawnLine.endsParagraph`가 가른다 (`HwpDrawnTextLayout.LineMetrics`). MS 워드
    /// 호환 문서의 세로 배치는 이 값 대신 문단 끝 글자의 **글꼴 상자**(`msWordParagraphEndBox`)를
    /// 읽는다.
    public static let paragraphEndBaseFontSize =
        NSAttributedString.Key("hwp.paragraphEndBaseFontSize")
    /// run의 글자 모양 id (NSNumber = `HwpCharShape` id, #187) — 조판
    /// (`HwpTextRunBuilder.attributes(for:script:)`)이 `HwpIndex`에 있는 글자 모양의 run에
    /// 싣는다 (없는 id의 폴백 모양은 키 없음). 한글은 MS 워드 호환 문서의 취소선을 **글자
    /// 모양 run** 단위로 그 run의 첫 글리프 글꼴에 놓으므로, 렌더러는 CoreText가 스크립트
    /// 슬롯·대체 글꼴로 쪼갠 잇닿은 run을 이 id로 다시 묶는다
    /// (`HwpPageLayerDecorations.msWordStrikethroughFonts`). 글자 모양이 다른 이웃 run은
    /// 크기·색이 같아도 묶이지 않는다.
    public static let charShapeId = NSAttributedString.Key("hwp.charShapeId")
    /// 양각/음각 (NSNumber: 1 양각, 2 음각) — 밝은/어두운 오프셋 사본 3-pass
    public static let reliefStyle = NSAttributedString.Key("hwp.reliefStyle")
    /// 양각/음각 run의 실제 글자색 (CGColor) — 글리프 자체는
    /// kCTForegroundColorFromContext로 그려서 사본 색을 컨텍스트로 바꾼다
    public static let reliefFaceColor = NSAttributedString.Key("hwp.reliefFaceColor")
    /// 강조점 (NSNumber != 0) — 글리프 위 가운데 점
    public static let emphasisMark = NSAttributedString.Key("hwp.emphasisMark")
    /// 글자 위치 (표 33 location) — 줄 안 세로 오프셋 (pt, 양수 = 위).
    /// 렌더러가 이 값으로 글리프를 직접 시프트한다 — 도입 근거였던 "CTFramesetter가
    /// kCTBaselineOffset을 무시한다"는 macOS 27.0에서 거짓이다 (`HwpTextRunBuilder`).
    public static let glyphBaselineOffset = NSAttributedString.Key("hwp.glyphBaselineOffset")
    /// 위/아래 첨자(표 33)의 베이스라인 이동량만 (pt, 양수 = 위, #179) —
    /// `glyphBaselineOffset`은 글자 위치와 첨자 이동의 **합**이라 둘을 가를 수 없는데,
    /// 장식선은 둘을 다르게 따른다: 한글은 취소선·글자 가운데 밑줄을 첨자로 옮겨진
    /// 베이스라인에 그리지만 글자 위치로 옮겨진 글리프는 따라가지 않는다 (2026-09-15
    /// 실측, `HwpPageLayerDecorations.drawStrikethroughIfNeeded`). 글리프 그리기·기하
    /// 질의·서식 복사는 종전대로 합산 키만 본다.
    public static let scriptBaselineOffset = NSAttributedString.Key("hwp.scriptBaselineOffset")
    /// 밑줄 여부 (글자 아래) — CT 밑줄 대신 렌더러가 직접 그린다: 선의 위 가장자리가 줄
    /// 상자 바닥(베이스라인 아래 `underlineBelowEdgeRatio` × 줄 상자 높이)에 붙고 두께는 줄
    /// 글자 기본 크기 × `decorationLineThicknessRatio`다 (#176·#226 — 줄 단위,
    /// `HwpDecorationLineGeometry.UnderlineReference`)
    public static let underlineStyle = NSAttributedString.Key("hwp.underlineStyle")
    /// 밑줄 '글자 위' 여부 (표 35 밑줄 종류 3) — 같은 두께의 선을 아래 가장자리가 줄 상자
    /// 상단(베이스라인 **위** `underlineAboveEdgeRatio` × 줄 상자 높이)에 붙게 그린다
    /// (#136·#226). 색은
    /// `underlineColor`를 공유한다. RTF 복사에는 싣지 않는다 (윗줄 속성이 없어
    /// 표준 밑줄로 바꾸면 위치가 뒤집힌다 — `HwpSelectionRTF` 주석).
    public static let underlineAboveStyle = NSAttributedString.Key("hwp.underlineAboveStyle")
    /// 밑줄 모양 (NSNumber = `HwpBorderType.rawValue`, 표 25 값 — 글자 모양의 4비트 값 +
    /// 1, #191) — 조판이 실선이 아닐 때만 싣는다. 글자 아래·위 밑줄이 공유한다. 렌더러는
    /// `HwpLineShapeGeometry`로 점선·파선·여러 줄·물결을 그리되 패턴을 **글자 모양 run**
    /// (같은 `charShapeId`의 잇닿은 CoreText run) 단위로 새로 시작한다 — 한글이 그렇다
    /// (2026-09-17 실측: 한 글자 모양 안의 한글↔라틴 전환은 패턴이 이어지고, 색만 다른
    /// 이웃 글자 모양은 다시 시작). RTF 복사에는 싣지 않는다 (`hwp.*` 일괄 제거).
    public static let underlineShape = NSAttributedString.Key("hwp.underlineShape")
    /// 취소선 모양 (NSNumber = `HwpBorderType.rawValue`, #191) — 밑줄 종류 '글자 가운데'와
    /// 취소선이 합류한 선은 밑줄 모양을 따른다 (한글은 취소선만 켠 글자 모양을 저장할 때
    /// 밑줄 모양 자리에 취소선 모양을 복사한다, #177).
    public static let strikethroughShape = NSAttributedString.Key("hwp.strikethroughShape")
    /// 상대크기 적용 전 기본 글자 크기 (pt) — % 줄 간격·줄 상자의 기준이고, 장식선
    /// (밑줄·취소선) 자리·두께의 크기 기준이기도 하다 (#226: 한글은 슬롯 상대 크기 전 이
    /// 크기로 장식선을 그린다 — `HwpPageLayerDecorations.decorationBaseFontSize`)
    public static let baseFontSize = NSAttributedString.Key("hwp.baseFontSize")
    /// 고정 공백 폭 (0.5em)의 기준 크기 — 상대크기는 반영, 첨자 축소는
    /// 제외한 글자 크기 (라운드 12 실측: 상대크기 170 줄 공백도 1.7배).
    /// 조판(`HwpTextRunBuilder.attributes(for:script:)`)이 **모든 run**에 싣는다 —
    /// 취소선의 첨자 축소 비율(run 글꼴 크기 ÷ 이 값)과, 기본 크기 키가 없는 문자열의
    /// 장식선 크기 폴백으로 읽는다 (`HwpPageLayerDecorations.preScriptFontSize`; 한글 문서의
    /// 장식선 크기 자체는 #226부터 `baseFontSize`다 — 이 값은 슬롯 상대 크기를 반영해 기본
    /// 40pt·50% run의 선을 20pt 자리에 그렸다). MS 워드 호환 문서의 선 모양 축척도 이
    /// 값이다 — 한글 2007 호환 문서의 선 모양은 크기와 무관한 고정 축척이다 (#227,
    /// `HwpLineShapeGeometry.Scale.hwp200XCharacterLine`).
    public static let spaceTargetSize = NSAttributedString.Key("hwp.spaceTargetSize")
    /// 문단이 다음 단/쪽으로 이어지는 조각의 마커 (NSNumber true, 조각 **전체**에 붙고
    /// 읽는 쪽은 끝 글자로 판정한다 — `HwpTableSplitter.markedAsContinuedFragment`) — 이
    /// 조각의 끝 줄은 문단 마지막 줄이 아니므로 양쪽 정렬을 유지하고(`HwpWordJustification`),
    /// 복사가 다음 조각을 잇고(`HwpSelectionGeometry`), MS 워드 호환 문단 끝 상자가 들지
    /// 않는다(`HwpDrawnLine.endsParagraph`). 쪽·단·표·각주의 모든 분할 경로가 단다.
    public static let continuedParagraphFragment =
        NSAttributedString.Key("hwp.continuedParagraphFragment")
    /// 단별 줄 캐시 run으로 놓인 조각의 **그 run 마지막 줄 줄 간격** (NSNumber pt, 조각 전체에
    /// 붙고 읽는 쪽은 끝 글자로 판정한다 — `HwpTableSplitter.marked(_:cachedTrailingLineSpacing:)`).
    /// 단 경계마다 `lineLocation`이 0으로 돌아가는 정상 다단 캐시는 문단 전체의 단조 증가
    /// 검사(`isValidLineSegmentCache`)에 걸리므로, 단 구분선 바닥(#191)이 문단 캐시 대신 이
    /// 값을 읽는다 (PR 리뷰: 배치는 캐시 높이인데 구분선만 측정 간격을 빼 길어졌다).
    public static let cachedTrailingLineSpacing =
        NSAttributedString.Key("hwp.cachedTrailingLineSpacing")

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
    /// 변경 추적 삽입 밑줄 (CGColor) — 일반 '글자 아래' 밑줄과 같은 자리·같은 두께로
    /// 이 색으로 그린다 (#187 실측: 한글 문서 13개 글꼴·MS 워드 호환 문서 32개 글꼴
    /// 전부 삽입 밑줄 = 일반 밑줄). 종전(#176)의 전용 상수 −0.26em·0.064em은
    /// `track-changes` 실물(MS 워드 호환 문서)의 함초롬돋움 값이었다.
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
    /// 한 줄 끝(코드 10) run 표식 (NSNumber true, #146) —
    /// `HwpTextRunBuilder.appendLineBreak`가 낸 U+000A 한 글자에 붙는다. 그 run은
    /// 줄 나눔과 줄 높이(글꼴·`baseFontSize`)에만 참여하고 **글리프는 그리지
    /// 않는다** — 렌더러(`HwpPageLayer.drawRun`)가 이 표식의 run을 건너뛴다. 한컴
    /// 번들의 HY 계열 폰트가 U+000A에 잉크 있는 글리프를 갖고 있어, 그대로 그리면
    /// Shift+Enter 자리마다 조판 부호가 보였다. 글자 자체는 원문 그대로 U+000A라
    /// 복사·낭독·검색은 표식과 무관하게 종전과 같다.
    public static let lineBreak = NSAttributedString.Key("hwp.lineBreak")
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
    /// 문단 전체를 잰 줄에서 잘라낸 **조각** 표식 (NSNumber true, #166) — 쪽·단 경계
    /// 흐름 분할(`HwpPaginator.appendLineSliceBlock`)·표 행 분할(`HwpTableSplitter`)·
    /// 다단 균형 재배치(`HwpColumnBandController`)가 **측정한 줄 전진량**으로 높이를 잡아
    /// 놓는 조각 문자열 **전체**에 붙는다 (`HwpParagraphLayout.measuredLineFragment`).
    /// 그 블록의 높이는 문단 전체 측정의 줄바꿈에서 왔으므로 렌더러는 같은 줄바꿈을 그려야
    /// 한다 — 문단 단위 한 줄 넘침 허용 규칙(`HwpDrawnTextLayout.slightOverflowLineMetrics`)을
    /// 조각 문자열에 다시 적용하면, 문단 전체로는 접히지 않던 두 줄이 조각만으로는 허용
    /// 배율 안에 들어 한 줄로 접히고 조각 아래에 그 줄만큼 빈 공간이 남는다. 한글이 저장한
    /// 높이를 따르는 조각(절대 캐시 run·다단 캐시 run·각주 이어짐)에는 붙이지 않는다 —
    /// 그쪽 높이는 측정 줄이 아니라 캐시라 접힘이 캐시 줄 수와 맞는 쪽일 수도 있다.
    /// `continuedParagraphFragment`(다음 단·쪽으로 **이어지는** 조각의 끝 글자)와 다른
    /// 축이다 — 그쪽은 문단의 마지막 조각엔 없다.
    public static let measuredLineFragment =
        NSAttributedString.Key("hwp.measuredLineFragment")
    /// 컨테이너 블록의 **결합 문자열 문단 구분자** 표식 (NSNumber true, #223) —
    /// `HwpCombinedBlockString`이 문단 사이에 넣은 `\n`에 붙는다. 그 글자는 앞 문단의
    /// 문단 끝 글자(CR) 자리라, MS 워드 호환 줄 상자에서 글자 상자가 아니라 문단 끝
    /// 상자(`msWordParagraphEndBox`) 쪽이다 (`HwpDrawnTextLayout.LineMetrics`) — 글자로
    /// 세면 개체로 끝나는 문단이 홀로 잰 상자(개체 높이)와 결합 문자열에서 잰 상자(개체 +
    /// 구분자 글꼴의 아래 몫)가 갈린다.
    static let combinedParagraphSeparator =
        NSAttributedString.Key("hwp.combinedParagraphSeparator")
}

import CoreHwp
import CoreText
import Foundation

/// 한 줄 끝(코드 10)의 조판 — 줄은 나누되 글리프는 그리지 않는 전용 run (#146).
extension HwpTextRunBuilder {
    /// 한 줄 끝 run이 유지하는 속성 — 줄 **높이**를 정하는 것(글꼴·비율 줄 간격의
    /// 기준 크기)과, 복사 문자열이 종전과 같도록 글자 색만 남긴다. 허용 목록인
    /// 이유는 빈 줄 앵커(`emptyLastLineAnchorAttributes`)와 같다: 장식은 글리프가
    /// 아니라 run 폭에 그려지므로(`HwpPageLayerDecorations.runBounds`) 밑줄·취소선·
    /// 음영을 물려받으면 진행 폭이 있는 폰트에서 줄 끝에 장식 토막이 남고, 장식
    /// 키가 늘어도 이 run이 새 장식을 받지 않아야 한다.
    static let lineBreakAttributes: [NSAttributedString.Key] = [
        kCTFontAttributeName as NSAttributedString.Key,
        HwpAttributedStringKey.baseFontSize,
        kCTForegroundColorAttributeName as NSAttributedString.Key,
    ]

    /// 방출 텍스트가 한 줄 끝(U+000A)으로 끝나는가 — `accumulate`가 이 글자를 일반
    /// chunk 대신 `splitLineBreak`로 보내는 술어. 한 줄 끝은 `HwpParaText`가 코드
    /// 10을 그대로 보존한 문자라 `string(from:)`이 U+000A로 낸다 (`controlText`는
    /// 접지 않는다). 앞에 잔여 lone surrogate가 붙을 수 있어 마지막 스칼라만 본다.
    static func endsWithLineBreak(_ text: String) -> Bool {
        text.unicodeScalars.last == "\u{000A}"
    }

    /// 한 줄 끝을 품은 방출 텍스트를 가른다: 앞부분(있다면 lone surrogate)은 일반
    /// chunk로, 한 줄 끝 자체는 전용 run으로 낸다. 현재 chunk는 그 앞에서 닫고
    /// 뒤에 새로 시작한다 — 컨트롤 마커와 같은 경계 규약이다.
    // swiftlint:disable:next function_parameter_count
    func splitLineBreak(
        _ text: String,
        shapeId: UInt32,
        trackMark: UInt32,
        memoAnchor: Bool,
        into chunk: inout Chunk,
        paragraph: CoreHwp.HwpParagraph,
        to output: NSMutableAttributedString
    ) {
        let prefix = String(text.unicodeScalars.dropLast())
        if !prefix.isEmpty {
            accumulate(
                prefix, shapeId: shapeId, trackMark: trackMark, memoAnchor: memoAnchor,
                into: &chunk, paragraph: paragraph, to: output
            )
        }
        let script = chunk.script ?? .korean
        append(chunk, paragraph: paragraph, to: output)
        appendLineBreak(shapeId: shapeId, script: script, paragraph: paragraph, to: output)
        chunk = Chunk(shapeId: shapeId, script: nil)
    }

    /// 한 줄 끝(10)을 **글리프 없는 줄 나눔**으로 낸다.
    ///
    /// U+000A는 남아야 한다 — CoreText의 하드 개행이고 복사 문자열의 줄 나눔이다
    /// (`controlText`가 13·24처럼 접지 않는 이유). 문제는 그 글자가 **그려진다**는
    /// 것이다: `HwpScript.detect`의 default가 `.english`라 라틴 슬롯 폰트로 조판되고,
    /// 한컴오피스 12.30 번들의 HY 계열 폰트(HY울릉도M·HYnamM 등)는 U+000A에 잉크
    /// 있는 글리프(진행 폭 1em, 잉크 0.9×0.37em)를 갖는다 — 실측 2026-09-09
    /// 15pt HY울릉도M: "구 분"에 한 줄 끝을 붙이면 어두운 픽셀 193 → 227, 잉크의
    /// 오른쪽 끝 x 37 → 52. 함초롬·Apple SD Gothic Neo·Helvetica는 글리프가 있어도
    /// 잉크가 없다. CoreText는 이 글리프를 줄 폭에 넣지 않으므로
    /// (`CTLineGetTypographicBounds`가 "구 분"과 "구 분\n"에서 같은 37.5) 줄 나눔·
    /// 정렬은 어느 폰트에서도 그대로다.
    ///
    /// 해법은 둘이다.
    /// 1. **표식**(`HwpAttributedStringKey.lineBreak`) — 렌더러가 표식 run의 글리프를
    ///    건너뛴다 (`HwpPageLayer.drawRun`). 글자 색을 투명하게 해 감추지 않는 이유는
    ///    그 색이 복사 RTF(`HwpSelectionRTF`)와 PDF에 그대로 실리기 때문이다 — 색은
    ///    원문 그대로 두고 그리기만 건너뛴다.
    /// 2. **글꼴은 직전 run의 스크립트 슬롯을 물려받는다** (`script`) — 라틴 슬롯
    ///    폰트가 본문 글꼴과 다르면 CTLine ascent를 자기 기준으로 끌어올려 줄
    ///    높이가 부푼다 (#137이 문단 끝 코드에서 겪은 것과 같은 축). 같은 글꼴이면
    ///    이 run은 줄 높이에 아무것도 더하지 않는다. 글자 모양은 한 줄 끝 자신의
    ///    것(`shapeId`)을 쓴다 — 그 글자의 크기가 줄 높이에 참여하는 것은 한글과
    ///    같다. 직전 run이 없으면(문단 첫 글자·컨트롤 마커 바로 뒤) 한글 슬롯이다 —
    ///    빈 문단 앵커(`emptyParagraphAnchor`)와 같은 선택이고, 비율 줄 간격의 빈
    ///    첫 줄이 다음 줄과 같은 높이를 갖는다 (실측 15pt·160%: 라틴 슬롯
    ///    Helvetica로 조판한 빈 첫 줄은 23pt, 한글 슬롯 HY울릉도M이면 다음 줄과 같은
    ///    24pt).
    ///
    /// 속성은 허용 목록(`lineBreakAttributes`)으로 깎는다 — 변경 추적 표시·메모
    /// 강조·장식은 run 폭에 그려지므로 물려받으면 줄 끝에 토막이 남는다.
    func appendLineBreak(
        shapeId: UInt32,
        script: HwpScript,
        paragraph: CoreHwp.HwpParagraph,
        to output: NSMutableAttributedString
    ) {
        let resolved = resolvedShape(id: shapeId, paragraph: paragraph)
        let existing = attributes(for: resolved, script: script)
        var kept: [NSAttributedString.Key: Any] = [
            HwpAttributedStringKey.lineBreak: NSNumber(value: true),
        ]
        for key in Self.lineBreakAttributes {
            kept[key] = existing[key]
        }
        output.append(NSAttributedString(string: "\u{000A}", attributes: kept))
    }
}

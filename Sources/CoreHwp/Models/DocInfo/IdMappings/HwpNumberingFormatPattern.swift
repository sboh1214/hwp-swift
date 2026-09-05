import Foundation

/**
 번호 형식 문자열의 분해 결과 — 문자 그대로의 조각과 수준 번호 참조.

 `HwpNumberingFormat.format`은 `^`로 시작하는 지시자로 번호 자리를 표시한다.
 실문서(헌법주석·noori·빈 문서 기본값)의 형식은 `^1.`·`^2.`·`(^4)`·`^6)`·`^7`
 꼴이고, 캐럿 뒤 숫자는 **참조할 수준**이다 — 4수준 정의의 `(^4)`는 4수준
 번호를 괄호로 감싸고, 상위 수준을 함께 적는 `^1.^2` 같은 형식도 이 규칙으로
 읽힌다. 스펙이 적은 `^n`(레벨 경로 1.1.1)과 `^N`(경로 + 마침표)은 문자
 그대로의 n·N이며 숫자 참조와 다른 토큰이다.

 지시자의 경계는 2026-09-05 한글.app 12.30 개요 번호 사용자 정의 대화상자의
 미리보기로 실측했다 (`outline-numbering` 픽스처 쌍의 9·10수준 형식이 그
 견본이다):
 - 캐럿은 **숫자 한 자리(1-9)**만 먹는다 — `^10`은 10수준이 아니라 `^1` 뒤에 문자
   `0`이다 (10수준 정의에 `^9.^10)`을 넣으면 `ㄱ.I0)`로 그려진다). 그래서
   `.level`은 1-9뿐이고, 10수준은 자기 번호를 숫자 참조로 적을 수 없다.
 - `^n`은 1수준부터 **그 정의 수준까지**의 번호를 각 수준의 번호 모양으로
   `.`로 이어 붙인 경로다 (10수준에서 `I.가.1.가.1.가.①.㉮.ㄱ.i`), `^N`은 그
   뒤에 마침표를 하나 더 찍는다. 렌더는 아직 지원하지 않는다 —
   `.levelPath`로 구분만 하고 `isSupported`가 거짓이 된다 (#153).
 - 그 밖의 캐럿은 지시자가 아니라 **다음 글자와 함께** 문자 그대로 그려진다
   (`^0)`→`^0)`, `^x^^)`→`^x^^)`, `^^1)`→`^^1)`, `^^^1)`→`^^I)`, `^a^1)`→`^aI)`,
   끝의 `^`는 혼자). 캐럿이 짝을 이룬 뒤에야 다음 캐럿이 지시자가 되므로
   `^^1`은 1수준 참조가 아니다. 그래서 별도 토큰 없이 두 글자를 `.literal`에
   합친다 — 임의의 번호로 읽지 않으면서 한글과 같은 글자가 된다. 예외적으로
   `^^n)`은 한글이 `^^` 뒤에 경로(첫 수준이 숫자 1로 보이는)를 그리는 특이
   경로를 탔는데, 실문서에 있을 수 없는 형식이라 모델링하지 않고 여기서는
   `^^n)` 문자 그대로다.

 분해는 순수 함수라 문서 순서·카운터와 무관하다 — 문단별 번호 문자열 조립은
 #153이 이 토큰 위에서 한다.
 */
public struct HwpNumberingFormatPattern: HwpPrimitive {
    /// 형식 문자열의 조각 하나.
    public enum Token: HwpPrimitive {
        /// 문자 그대로 표시할 조각 — 인접한 문자는 하나로 합치고, 지시자가 아닌
        /// 캐럿은 다음 글자와 함께(`^0`·`^x`·`^^`, 끝의 `^`는 혼자) 여기에 든다.
        case literal(String)
        /// 수준 1-9의 번호 자리 — `^1`…`^9`. 캐럿은 숫자 한 자리만 먹는다.
        case level(Int)
        /// 레벨 경로 — `^n`(1.1.1) 또는 마침표를 하나 더 찍는 `^N`(1.1.1.).
        /// 스펙에는 있으나 아직 지원하지 않는다.
        case levelPath(trailingPeriod: Bool)
    }

    /// 숫자 참조로 가리킬 수 있는 수준 — 캐럿이 한 자리만 먹으므로 1-9다
    /// (정의의 수준 범위 1-10과 다르다: `HwpNumbering.format(forLevel:)`).
    public static let referenceLevelRange = 1 ... 9

    /// 문서 순서의 토큰.
    public let tokens: [Token]

    public init(tokens: [Token]) {
        self.tokens = tokens
    }

    /// `.level` 토큰이 참조하는 수준을 등장 순서대로 (중복 포함).
    public var referencedLevels: [Int] {
        tokens.compactMap { token in
            if case let .level(level) = token {
                return level
            }
            return nil
        }
    }

    /// 모든 토큰이 문자 조각이거나 수준 참조인가 — 거짓이면(레벨 경로) 렌더가
    /// 번호를 만들지 않고 진단으로 남겨야 한다.
    public var isSupported: Bool {
        tokens.allSatisfy { token in
            switch token {
            case .literal, .level:
                true
            case .levelPath:
                false
            }
        }
    }

    /// 형식 문자열을 분해한다.
    public static func parse(_ format: String) -> HwpNumberingFormatPattern {
        var tokens: [Token] = []
        var literal = String.UnicodeScalarView()
        func flushLiteral() {
            if !literal.isEmpty {
                tokens.append(.literal(String(literal)))
                literal = String.UnicodeScalarView()
            }
        }

        // 유니코드 스칼라 단위로 본다 — 한글은 WCHAR(UTF-16 단위) 스트림을 훑으므로
        // 숫자 뒤에 결합 문자가 와도(`^1\u{0301}`) 지시자다. Character 단위로 돌면
        // `1` + U+0301이 한 클러스터로 붙어 `"1"`과 달라져 지시자를 놓친다. 지시자
        // 글자가 전부 BMP ASCII라 스칼라 스캔은 UTF-16 스캔과 결과가 같다.
        let scalars: [Unicode.Scalar] = Array(format.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let next: Unicode.Scalar? = index + 1 < scalars.count ? scalars[index + 1] : nil
            guard scalar == "^" else {
                literal.append(scalar)
                index += 1
                continue
            }
            if let token = directive(after: next) {
                flushLiteral()
                tokens.append(token)
                index += 2
                continue
            }
            // 지시자가 아닌 캐럿은 다음 글자를 **함께** 소비해 문자 그대로 남긴다 —
            // 한글.app 실측 `^^1)` → `^^1)`(둘째 캐럿이 1을 먹지 않는다),
            // `^^^1)` → `^^I)`, `^a^1)` → `^aI)`. 끝의 캐럿은 혼자 남는다.
            literal.append(scalar)
            if let next {
                literal.append(next)
                index += 2
            } else {
                index += 1
            }
        }
        flushLiteral()
        return HwpNumberingFormatPattern(tokens: tokens)
    }

    /// 캐럿 다음 글자 하나가 만드는 지시자 — 숫자 1-9·n·N 밖이면 nil(문자 그대로).
    private static func directive(after scalar: Unicode.Scalar?) -> Token? {
        switch scalar {
        case "n":
            .levelPath(trailingPeriod: false)
        case "N":
            .levelPath(trailingPeriod: true)
        case let digit? where ("1" ... "9").contains(digit):
            .level(Int(digit.value - Unicode.Scalar("0").value))
        default:
            nil
        }
    }
}

public extension HwpNumberingFormat {
    /// `format`을 문자 조각과 수준 참조로 분해한 결과.
    var pattern: HwpNumberingFormatPattern {
        HwpNumberingFormatPattern.parse(format)
    }
}

public extension HwpNumbering {
    /// 사람이 읽는 수준(1-10)의 번호 형식 — 1-7은 `formatArray`, 8-10은
    /// `extendedFormatArray`(5.1.0.0 이상에만 있다). 범위 밖이거나 그 수준의
    /// 배열이 없으면 nil.
    func format(forLevel level: Int) -> HwpNumberingFormat? {
        guard (1 ... 10).contains(level) else {
            return nil
        }
        if level <= 7 {
            return formatArray.indices.contains(level - 1) ? formatArray[level - 1] : nil
        }
        guard let extended = extendedFormatArray, extended.indices.contains(level - 8) else {
            return nil
        }
        return extended[level - 8]
    }
}

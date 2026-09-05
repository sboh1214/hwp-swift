import Foundation

/**
 번호 형식 문자열의 분해 결과 — 문자 그대로의 조각과 수준 번호 참조.

 `HwpNumberingFormat.format`은 `^`로 시작하는 지시자로 번호 자리를 표시한다.
 실문서(헌법주석·noori·빈 문서 기본값)의 형식은 `^1.`·`^2.`·`(^4)`·`^6)`·`^7`
 꼴이고, 캐럿 뒤 숫자는 **참조할 수준**이다 — 4수준 정의의 `(^4)`는 4수준
 번호를 괄호로 감싸고, 상위 수준을 함께 적는 `^1.^2` 같은 형식도 이 규칙으로
 읽힌다. 스펙이 적은 `^n`(레벨 경로 1.1.1)과 `^N`(경로 + 마침표)은 문자
 그대로의 n·N이며 숫자 참조와 다른 토큰이다. 둘은 실문서 견본이 없어
 `.levelPath`로 구분만 하고 아직 지원하지 않는다.

 지원 범위 밖 지시자 — 캐럿 뒤에 숫자·n·N이 아닌 문자가 오거나 캐럿으로
 끝나는 형식, 1-10 밖의 수준(`^0`·`^11`) — 는 `.unsupported`에 원문을 남긴다.
 렌더가 그런 형식을 임의의 번호로 그리지 않도록 `isSupported`가 거짓이 된다
 (#151 "지원하지 못하는 형식을 임의의 번호로 표시하지 않는다"). `^10`은
 10수준 참조로 읽는다 — 두 자리 숫자 중 유일하게 수준 범위(표 38의 수준
 1-10) 안이며, `^1` 뒤에 문자 그대로의 `0`을 붙인 형식은 실문서에 없다.
 이 두 자리 해석은 실파일 검증 대기 항목이다.

 분해는 순수 함수라 문서 순서·카운터와 무관하다 — 문단별 번호 문자열 조립은
 #153이 이 토큰 위에서 한다.
 */
public struct HwpNumberingFormatPattern: HwpPrimitive {
    /// 형식 문자열의 조각 하나.
    public enum Token: HwpPrimitive {
        /// 문자 그대로 표시할 조각 — 인접한 문자는 하나로 합친다.
        case literal(String)
        /// 수준 N(1-10)의 번호 자리 — `^N`.
        case level(Int)
        /// 레벨 경로 — `^n`(1.1.1) 또는 마침표를 하나 더 찍는 `^N`(1.1.1.).
        /// 스펙에는 있으나 아직 지원하지 않는다.
        case levelPath(trailingPeriod: Bool)
        /// 해석하지 못한 캐럿 지시자 — 캐럿과 그 뒤 문자(또는 숫자열) 원문.
        case unsupported(String)
    }

    /// 표 38이 정의하는 수준 범위 — 기본 7 + 확장 3.
    public static let levelRange = 1 ... 10

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

    /// 모든 토큰이 문자 조각이거나 수준 참조인가 — 거짓이면 렌더가 번호를
    /// 만들지 않고 진단으로 남겨야 한다.
    public var isSupported: Bool {
        tokens.allSatisfy { token in
            switch token {
            case .literal, .level:
                true
            case .levelPath, .unsupported:
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

        // 유니코드 스칼라 단위로 본다 — 캐럿과 ASCII 숫자는 결합 문자와 클러스터를
        // 이루지 않으므로 Character 단위와 결과가 같고, 원문 조각을 그대로
        // 돌려주는 데는 스칼라가 정확하다.
        let scalars: [Unicode.Scalar] = Array(format.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "^" else {
                literal.append(scalar)
                index += 1
                continue
            }
            flushLiteral()
            let next: Unicode.Scalar? = index + 1 < scalars.count ? scalars[index + 1] : nil
            switch next {
            case "n":
                tokens.append(.levelPath(trailingPeriod: false))
                index += 2
            case "N":
                tokens.append(.levelPath(trailingPeriod: true))
                index += 2
            case let digit? where isASCIIDigit(digit):
                let (token, cursor) = levelToken(in: scalars, from: index + 1)
                tokens.append(token)
                index = cursor
            case let other?:
                tokens.append(.unsupported("^" + String(other)))
                index += 2
            case nil:
                tokens.append(.unsupported("^"))
                index += 1
            }
        }
        flushLiteral()
        return HwpNumberingFormatPattern(tokens: tokens)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0" ... "9").contains(scalar)
    }

    /// 캐럿 뒤 숫자열 → 수준 토큰과 그다음 위치. 숫자열은 통째로 읽는다 —
    /// `^12`를 `^1` + `2`로 가르지 않고 미지원으로 남긴다.
    private static func levelToken(
        in scalars: [Unicode.Scalar], from start: Int
    ) -> (Token, Int) {
        var digits = ""
        var cursor = start
        while cursor < scalars.count, isASCIIDigit(scalars[cursor]) {
            digits.unicodeScalars.append(scalars[cursor])
            cursor += 1
        }
        if let level = Int(digits), levelRange.contains(level),
           digits.count == (level == 10 ? 2 : 1)
        {
            return (.level(level), cursor)
        }
        return (.unsupported("^" + digits), cursor)
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
        guard HwpNumberingFormatPattern.levelRange.contains(level) else {
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

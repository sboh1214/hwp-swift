import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 수식 (eqed) 컨트롤의 EQEDIT 스크립트를 한 줄 텍스트로 근사해 그린다.
///
/// EQEDIT 조판 엔진 없이: 스페이싱 토큰 (`` ` ``/`~`)을 공백으로, 기호 토큰을
/// 유니코드로 치환하고, 관계 연산자 주변을 한글.app처럼 한 칸 띄운다
/// (`x=1` → `x = 1`). 분수 (`over`)/근호 (`sqrt`) 같은 구조 토큰은 스크립트
/// 원문 그대로 남는다 — 구조 조판은 근사 범위 밖 (아무것도 안 그리는 것보다
/// 스크립트 노출이 한글.app 결과에 가깝다).
enum HwpEquationLayout {
    /// 영문 단어 토큰 → 유니코드 기호 (단어 경계 치환)
    private static let wordTokens: [String: String] = [
        "times": "×", "divide": "÷", "cdot": "·", "leq": "≤", "geq": "≥",
        "neq": "≠", "inf": "∞", "infty": "∞",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ",
        "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "chi": "χ",
        "psi": "ψ", "omega": "ω",
    ]

    /// 기호열 토큰 (긴 것부터 치환)
    private static let symbolTokens: [(token: String, symbol: String)] = [
        ("<->", "↔"), ("->", "→"), ("<-", "←"), ("<=", "≤"), (">=", "≥"),
        ("!=", "≠"), ("+-", "±"), ("-+", "∓"),
    ]

    /// 관계 연산자 — 한글.app 수식 렌더처럼 양쪽에 한 칸을 보장한다
    private static let relationOperators: Set<Character> = ["=", "<", ">", "≤", "≥", "≠"]

    /// EQEDIT 스크립트 → 표시 문자열
    static func displayText(fromScript script: String) -> String {
        var text = script
            .replacingOccurrences(of: "`", with: " ")
            .replacingOccurrences(of: "~", with: " ")
        for (token, symbol) in symbolTokens {
            text = text.replacingOccurrences(of: token, with: symbol)
        }
        for (token, symbol) in wordTokens {
            text = text.replacingOccurrences(
                of: "\\b\(token)\\b",
                with: symbol,
                options: .regularExpression
            )
        }

        var spaced = ""
        // 관계 연산자 양쪽은 얇은 공백 (U+2009) — 실물 'x = 1' 간격 실측
        let thinSpace: Character = "\u{2009}"
        for character in text {
            if relationOperators.contains(character) {
                if let last = spaced.last, last != " ", last != thinSpace {
                    spaced.append(thinSpace)
                }
                spaced.append(character)
                spaced.append(thinSpace)
            } else if character == " " {
                if spaced.last != " " {
                    spaced.append(character)
                }
            } else {
                spaced.append(character)
            }
        }
        return spaced.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{2009}"))
    }

    /// eqEdit 정보로 CT 속성 문자열을 만든다. 라틴 문자는 수학 관례대로 이탤릭,
    /// 숫자/연산자는 정립. 글자 크기는 EQEDIT letterSize (HWPUNIT).
    static func attributedString(
        edit: CoreHwp.HwpEquationEdit,
        fallbackSize: CGFloat,
        fontResolver: HwpFontResolver
    ) -> NSAttributedString? {
        guard let script = edit.equationText else { return nil }
        let text = displayText(fromScript: script)
        guard !text.isEmpty else { return nil }

        let letterSize = edit.letterSize.map { HwpUnits.points(fromHwpUnitU: $0) } ?? 0
        let size = max(
            1,
            (letterSize > 0 ? letterSize : fallbackSize) * HwpRenderTuning.Equation.glyphScale
        )
        let baseFont = fontResolver.resolve(
            faceName: edit.fontName ?? "HancomEQN",
            script: .english,
            size: size
        )
        let italicFont: CTFont
        if let traitCopy = CTFontCreateCopyWithSymbolicTraits(
            baseFont, 0, nil, .traitItalic, .traitItalic
        ) {
            italicFont = traitCopy
        } else {
            // 이탤릭 페이스 없는 폰트 (HancomEQN): 기울임 매트릭스 근사
            var matrix = CTFontGetMatrix(baseFont)
            matrix.c += 0.22
            italicFont = CTFontCreateCopyWithAttributes(baseFont, 0, &matrix, nil)
        }
        let color = (edit.textColor ?? CoreHwp.HwpColor(0, 0, 0)).cgColor

        let fontKey = kCTFontAttributeName as NSAttributedString.Key
        let colorKey = kCTForegroundColorAttributeName as NSAttributedString.Key
        let result = NSMutableAttributedString()
        for character in text {
            let isLatinLetter = character.isLetter && character.isASCII
            result.append(NSAttributedString(
                string: String(character),
                attributes: [
                    fontKey: isLatinLetter ? italicFont : baseFont,
                    colorKey: color,
                ]
            ))
        }
        return result
    }
}

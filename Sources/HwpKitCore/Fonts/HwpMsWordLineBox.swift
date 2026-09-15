import CoreGraphics
import CoreText
import Foundation

/// MS 워드 호환 문서(`HwpCompatibleDocumentTarget.msWord`)에서 한글이 잡는 **줄 상자와
/// 장식선 기준 상자** (#187·#194) — 글꼴에서 읽으면 em 단위이고(`metrics(of:)`), 글자
/// 크기를 곱한 pt 상자(`scaled(by:)`)를 줄의 run들끼리 `union`하면 그 줄의 상자다.
///
/// 네이티브 문서의 줄 상자가 글꼴과 무관한 글자 크기(1em, 베이스라인 0.85em)인 것과
/// 달리, 한글은 MS 워드 호환 문서에서 글꼴의 OS/2 `usWinAscent`·`usWinDescent`로
/// 줄 상자를 잡고 밑줄·취소선·변경 추적 표시선을 그 상자에 맞춘다. 한글 12.30.0의
/// PDF 내보내기·줄 캐시(`hp:lineseg`) 실측(2026-09-15, 글꼴 32종 + OS/2 비트를 바꾼
/// 합성 글꼴 7종, 10·40·80pt)으로 확정한 규칙은 둘로 갈린다.
///
/// | 글꼴 | 줄 상자 `lineHeight` | 상자 상단 → 베이스라인 `baseline` |
/// | --- | --- | --- |
/// | CJK 글꼴 (OS/2 `ulUnicodeRange2`에 CJK 블록 비트) | 1.3 × win 상자 | winAscent + 0.15 × win 상자 |
/// | 그 밖 | win 상자 + hhea `lineGap` | winAscent + lineGap |
///
/// (win 상자 = winAscent + winDescent)
///
/// 장식선은 두 갈래 모두 **줄 상자에서 거꾸로 푼 상자**를 쓴다 — `cellHeight` =
/// `lineHeight` / 1.3, `ascent` = `baseline` − 0.15 × `cellHeight`, `descent` =
/// `cellHeight` − `ascent`. CJK 글꼴에서는 그것이 win 지표 그대로이고(함초롬돋움
/// 1.07/0.23, Apple SD 산돌고딕 Neo 0.90/0.30, HY울릉도M 0.8584/0.1416, Menlo
/// 0.9282/0.2358), 그 밖의 글꼴에서는 win 상자보다 작은 상자가 된다(Helvetica win
/// 0.9502/0.2251 → 0.8146/0.0895, Times New Roman 0.8911/0.2163 + gap 0.0425 →
/// 0.8009/0.0836). 어느 표(win·hhea·typo·bbox)로도 설명되지 않던 라틴 글꼴의 밑줄
/// 자리가 이 되풀이로 0.002em 안에서 맞는다.
///
/// **CJK 판정은 OS/2 `ulUnicodeRange2`의 비트 50–58·61**(CJK 기호·히라가나·가타카나·
/// 주음·한글 호환 자모·CJK 기타·CJK 괄호·CJK 호환·한글 음절·CJK 통합 한자)이다 —
/// 글리프가 아니라 **비트**다. Menlo·Baskerville은 CJK 글리프가 없는데도 비트 57(CJK
/// 호환)이 켜져 있어 CJK 갈래이고, Courier New·Times New Roman·Arial은 비트 63만
/// 있어 그 밖이다. 같은 Courier New에 비트 57을 켠 사본은 CJK 갈래로, Menlo에서 57·
/// 63을 끈 사본은 그 밖으로 옮겨 갔다(비트 50·58·61을 하나씩 켠 Georgia 사본은 전부
/// CJK 갈래, 63만 켠 사본은 그 밖). 레이아웃 호환성 플래그(표 56)는 관여하지 않는다.
///
/// OS/2 표가 없는 글꼴(AppleMyungjo·AppleGothic)은 hhea ascent·descent를 win 지표
/// 자리에 쓰고 CJK 비트가 없으므로 그 밖 갈래다 (실측 AppleMyungjo 0.727/0.178 =
/// hhea 0.8693/0.318 + gap 0으로 푼 값).
///
/// **한 줄의 상자는 run 상자들의 축별 최댓값이다** — 줄 상자 높이는 가장 큰 run의 것,
/// 베이스라인 자리도 가장 큰 run의 것이며 둘이 다른 run에서 올 수 있다 (한글 줄 캐시
/// 실측: Apple SD 산돌고딕 Neo 20pt 글자 + Menlo 20pt 문단 끝 글자의 줄이 `vertsize`
/// 3119 = Apple SD의 1.5596em, `baseline` 2207 = Menlo의 1.1028em). 문단 끝 글자(CR)는
/// 마지막 글자 모양의 **라틴 슬롯** 글꼴로 그 줄에 든다 (같은 문단이 세 줄로 접히면
/// 앞 두 줄은 2160 = Apple SD의 1.08em, 끝 글자가 있는 마지막 줄만 2207). 장식선은
/// 그렇게 합친 줄 상자에서 `cellHeight`·`ascent`·`descent`를 다시 푼다.
public struct HwpMsWordLineBox: Hashable, Sendable {
    /// 줄 상자 높이 (em 또는 pt)
    public let lineHeight: CGFloat
    /// 줄 상자 상단에서 베이스라인까지 (em 또는 pt)
    public let baseline: CGFloat

    public init(lineHeight: CGFloat, baseline: CGFloat) {
        self.lineHeight = lineHeight
        self.baseline = baseline
    }

    /// 표 값에서 만든다 — `isCJK`가 두 갈래를 가른다.
    public init(
        winAscent: CGFloat, winDescent: CGFloat, lineGap: CGFloat, isCJK: Bool
    ) {
        let cell = winAscent + winDescent
        if isCJK {
            self.init(
                lineHeight: HwpRenderTuning.Text.msWordLineHeightCellRatio * cell,
                baseline: winAscent + HwpRenderTuning.Text.msWordBaselineMarginCellRatio * cell
            )
        } else {
            self.init(lineHeight: cell + lineGap, baseline: winAscent + lineGap)
        }
    }

    /// 글자 크기를 곱한 pt 상자.
    public func scaled(by fontSize: CGFloat) -> HwpMsWordLineBox {
        HwpMsWordLineBox(lineHeight: lineHeight * fontSize, baseline: baseline * fontSize)
    }

    /// 줄의 run 상자들을 합친 줄 상자 — 높이와 베이스라인 자리를 **각각** 최댓값으로
    /// 잡는다 (위 실측). 빈 줄이면 nil.
    public static func union(_ boxes: [HwpMsWordLineBox]) -> HwpMsWordLineBox? {
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { line, box in
            HwpMsWordLineBox(
                lineHeight: max(line.lineHeight, box.lineHeight),
                baseline: max(line.baseline, box.baseline)
            )
        }
    }

    /// 장식선 기준 상자 높이 = 줄 상자 / 1.3
    public var cellHeight: CGFloat {
        lineHeight / HwpRenderTuning.Text.msWordLineHeightCellRatio
    }

    /// 장식선 기준 상자의 베이스라인 위 높이
    public var ascent: CGFloat {
        baseline - HwpRenderTuning.Text.msWordBaselineMarginCellRatio * cellHeight
    }

    /// 장식선 기준 상자의 베이스라인 아래 깊이
    public var descent: CGFloat {
        cellHeight - ascent
    }

    /// 글꼴에서 em 단위로 읽는다 — OS/2·hhea 표를 직접 읽고 PostScript 이름으로
    /// 캐시한다 (같은 이름의 글꼴은 크기가 달라도 em 지표가 같다). 두 표가 다 없으면
    /// CoreText가 보고하는 ascent·descent·leading으로 떨어진다.
    public static func metrics(of font: CTFont) -> HwpMsWordLineBox {
        let key = CTFontCopyPostScriptName(font) as String
        return cache.metrics(for: key) { read(from: font) }
    }

    private static let cache = MetricsCache()

    /// 지표는 불변 값이라 사전 접근만 lock으로 감싼다 (`HwpFontResolver.FontCache`와
    /// 같은 패턴).
    private final class MetricsCache: @unchecked Sendable {
        private var storage: [String: HwpMsWordLineBox] = [:]
        private let lock = NSLock()

        func metrics(
            for key: String, create: () -> HwpMsWordLineBox
        ) -> HwpMsWordLineBox {
            lock.lock()
            if let cached = storage[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            let value = create()
            lock.lock()
            storage[key] = value
            lock.unlock()
            return value
        }
    }

    /// OS/2 `ulUnicodeRange2`의 CJK 블록 비트 (Unicode range 50–58·61). 59(비평면 0)·
    /// 60·62(사용자 영역)·63은 한글의 판정에 들지 않는다 — 63만 켠 Courier New·Times
    /// New Roman·Arial·Tahoma가 그 밖 갈래다.
    static let cjkUnicodeRange2Mask: UInt32 = {
        var mask: UInt32 = 0
        for bit in 50 ... 58 {
            mask |= 1 << UInt32(bit - 32)
        }
        mask |= 1 << UInt32(61 - 32)
        return mask
    }()

    static func read(from font: CTFont) -> HwpMsWordLineBox {
        let unitsPerEm = CGFloat(CTFontGetUnitsPerEm(font))
        guard unitsPerEm > 0 else {
            return fallback(from: font)
        }
        let hhea = CTFontCopyTable(font, CTFontTableTag(kCTFontTableHhea), []) as Data?
        // hhea: ascent 4·descent 6·lineGap 8 (FWORD)
        let lineGap = hhea.flatMap { $0.int16(at: 8) }.map { CGFloat($0) / unitsPerEm } ?? 0
        if let os2 = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?,
           let winAscent = os2.uint16(at: 74), let winDescent = os2.uint16(at: 76),
           winAscent + winDescent > 0
        {
            // OS/2: ulUnicodeRange2 46·usWinAscent 74·usWinDescent 76
            let range2 = os2.uint32(at: 46) ?? 0
            return HwpMsWordLineBox(
                winAscent: CGFloat(winAscent) / unitsPerEm,
                winDescent: CGFloat(winDescent) / unitsPerEm,
                lineGap: lineGap,
                isCJK: range2 & cjkUnicodeRange2Mask != 0
            )
        }
        if let hhea, let ascent = hhea.int16(at: 4), let descent = hhea.int16(at: 6),
           ascent > 0
        {
            return HwpMsWordLineBox(
                winAscent: CGFloat(ascent) / unitsPerEm,
                winDescent: CGFloat(abs(descent)) / unitsPerEm,
                lineGap: lineGap,
                isCJK: false
            )
        }
        return fallback(from: font)
    }

    /// 표를 못 읽는 글꼴 — CoreText 보고값(hhea 계열)으로 그 밖 갈래를 만든다.
    static func fallback(from font: CTFont) -> HwpMsWordLineBox {
        let size = CTFontGetSize(font)
        guard size > 0 else {
            return HwpMsWordLineBox(winAscent: 0.8, winDescent: 0.2, lineGap: 0, isCJK: false)
        }
        return HwpMsWordLineBox(
            winAscent: CTFontGetAscent(font) / size,
            winDescent: CTFontGetDescent(font) / size,
            lineGap: CTFontGetLeading(font) / size,
            isCJK: false
        )
    }
}

private extension Data {
    /// 빅엔디언 16비트 (표 오프셋은 sfnt 규약)
    func uint16(at offset: Int) -> UInt16? {
        guard count >= offset + 2 else { return nil }
        let index = startIndex + offset
        return UInt16(self[index]) << 8 | UInt16(self[index + 1])
    }

    func int16(at offset: Int) -> Int16? {
        uint16(at: offset).map { Int16(bitPattern: $0) }
    }

    func uint32(at offset: Int) -> UInt32? {
        guard count >= offset + 4 else { return nil }
        let index = startIndex + offset
        return UInt32(self[index]) << 24 | UInt32(self[index + 1]) << 16
            | UInt32(self[index + 2]) << 8 | UInt32(self[index + 3])
    }
}

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
/// 장식선은 두 갈래 모두 **줄 상자에서 거꾸로 푼 상자**를 쓴다 — 글꼴 하나의 상자와 그
/// 합(`init(lineHeight:baseline:)`·`union`)에서는 `cellHeight` = `lineHeight` / 1.3,
/// `ascent` = `baseline` − 0.15 × `cellHeight`, `descent` = `cellHeight` − `ascent` (줄 상자
/// 가장자리에서 0.15 cell씩 안쪽; 줄 끝 글자·개체가 키운 줄 상자는 아래 문단). CJK
/// 글꼴에서는 그것이 win 지표 그대로이고(함초롬돋움
/// 1.07/0.23, Apple SD 산돌고딕 Neo 0.90/0.30, HY울릉도M 0.8584/0.1416, Menlo
/// 0.9282/0.2358), 그 밖의 글꼴에서는 win 상자보다 작은 상자가 된다(Helvetica win
/// 0.9502/0.2251 → 0.8146/0.0895, Times New Roman 0.8911/0.2163 + gap 0.0425 →
/// 0.8009/0.0836). 어느 표(win·hhea·typo·bbox)로도 설명되지 않던 라틴 글꼴의 밑줄
/// 자리가 이 되풀이로 0.002em 안에서 맞는다.
///
/// **CJK 판정은 OS/2 `ulUnicodeRange2`의 비트 48–59·61**(OpenType 이름으로 48 CJK
/// 기호·49 히라가나·50 가타카나·51 주음·52 한글 호환 자모·53 파스파·54 CJK 괄호·55 CJK
/// 호환·56 한글 음절·57 비평면 0·58 페니키아·59 CJK 통합 한자·61 CJK 획/CJK 호환
/// 한자 — 이름과 무관하게 이 자리의 비트가 하나라도 켜져 있으면 된다)이다 — 글리프가
/// 아니라 **비트**다. Menlo·Baskerville은 CJK 글리프가 없는데도 비트 57(비평면 0)이
/// 켜져 있어 CJK 갈래이고, Courier New·Times New Roman·Arial은 비트 62·63만 있어 그
/// 밖이다. 같은 Courier New에 비트 57을 켠 사본은 CJK 갈래로, Menlo에서 57·63을 끈
/// 사본(60·62 잔류)은 그 밖으로 옮겨 갔고, Georgia(비트 없음)에 48·49·50·51·53·56·
/// 58·59·61을 하나씩 켠 사본은 전부 CJK 갈래, 60·62·63을 하나씩 켠 사본은 그 밖이다
/// (합성 글꼴 15종, 2026-09-15/16). 레이아웃 호환성 플래그(표 56)는 관여하지 않는다.
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
/// 앞 두 줄은 2160 = Apple SD의 1.08em, 끝 글자가 있는 마지막 줄만 2207). 다만 **끝
/// 글자 상자가 글자 상자보다 높으면** 합치지 않고 쌓는다 — 줄 상자 = 끝 글자 상자 높이 +
/// 글자 상자의 베이스라인 아래 몫이다 (#223, `HwpDrawnTextLayout.LineMetrics.msWordLineBox`;
/// 글자처럼 취급 개체도 같은 꼴). 그렇게 키운 줄 상자는 **글자 상자의 `cellHeight`**를 따로
/// 싣고(`init(lineHeight:baseline:cellHeight:)` — `lineHeight` / 1.3이 아니다), 장식선 기준
/// 상자(`ascent`·`descent`)는 그 줄 상자의 가장자리에서 그 cell의 0.15배 안쪽이다 — `descent`
/// = `lineHeight` − `baseline` − 0.15 × `cellHeight` (밑줄 중심은 가장자리에서 0.129 cell,
/// `HwpDecorationLineGeometry.msWordUnderlineBelow`).
public struct HwpMsWordLineBox: Hashable, Sendable {
    /// 줄 상자 높이 (em 또는 pt)
    public let lineHeight: CGFloat
    /// 줄 상자 상단에서 베이스라인까지 (em 또는 pt)
    public let baseline: CGFloat
    /// 장식선 기준 상자 높이 — 밑줄이 줄 상자 가장자리에서 들어오는 거리와 두께의 기준
    /// (`HwpDecorationLineGeometry.msWordUnderlineBelow`). 글꼴 하나의 상자나 글자 run들을
    /// 합친 상자는 줄 상자 / 1.3이고(`init(lineHeight:baseline:)`), 문단 끝 글자·개체가 줄
    /// 상자를 키운 줄에서는 **글자 상자**의 값이 남는다 (글자가 없는 줄은 줄 끝 글자 상자,
    /// 개체만 있는 줄은 개체 마커 글꼴의 값 — `HwpDrawnTextLayout.msWordLineBox(of:endsParagraph:)`) (#223 한글 12.30 PDF: 함초롬돋움
    /// 10pt 밑줄 + 16pt 문단 끝 글자 줄은 상자 31.32pt인데 밑줄 중심이 상자 바닥에서 1.71pt
    /// 위·두께 0.72pt(0.12pt 격자) — 글자 상자 cell 16.92 / 1.3의 산식 1.68·0.65에 맞고,
    /// 27.06 / 1.3이면 2.69·1.04, 31.32 / 1.3이면 3.11·1.20이다).
    public let cellHeight: CGFloat

    public init(lineHeight: CGFloat, baseline: CGFloat) {
        self.init(
            lineHeight: lineHeight, baseline: baseline,
            cellHeight: lineHeight / HwpRenderTuning.Text.msWordLineHeightCellRatio
        )
    }

    /// 장식선 기준 상자 높이를 따로 준다 — 줄 상자가 글자 상자보다 커진 줄 (#223).
    public init(lineHeight: CGFloat, baseline: CGFloat, cellHeight: CGFloat) {
        self.lineHeight = lineHeight
        self.baseline = baseline
        self.cellHeight = cellHeight
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

    /// 글자 크기를 곱한 pt 상자 — MS 워드 호환 문서에서는 run 글꼴 크기가 아니라 **글자
    /// 모양 기본 크기**(`hwp.baseFontSize`, 슬롯 상대 크기 무관)를 곱한다 (한글 실측,
    /// `HwpPageLayerDecorations.decorationBaseFontSize`).
    public func scaled(by fontSize: CGFloat) -> HwpMsWordLineBox {
        HwpMsWordLineBox(
            lineHeight: lineHeight * fontSize, baseline: baseline * fontSize,
            cellHeight: cellHeight * fontSize
        )
    }

    /// 줄의 글자 run 상자들을 합친 상자 — 높이와 베이스라인 자리를 **각각** 최댓값으로
    /// 잡는다 (위 실측; 장식선 기준 상자도 최댓값). 빈 줄이면 nil. 문단 끝 글자·개체는 이
    /// 합이 아니라 쌓는 규칙이다 (`HwpDrawnTextLayout.LineMetrics.msWordLineBox`, #223).
    public static func union(_ boxes: [HwpMsWordLineBox]) -> HwpMsWordLineBox? {
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { line, box in
            HwpMsWordLineBox(
                lineHeight: max(line.lineHeight, box.lineHeight),
                baseline: max(line.baseline, box.baseline),
                cellHeight: max(line.cellHeight, box.cellHeight)
            )
        }
    }

    /// 장식선 기준 상자의 베이스라인 위 높이 — 줄 상자 윗변에서 0.15 cell 아래.
    public var ascent: CGFloat {
        baseline - HwpRenderTuning.Text.msWordBaselineMarginCellRatio * cellHeight
    }

    /// 장식선 기준 상자의 베이스라인 아래 깊이 — 줄 상자 바닥에서 0.15 cell 위. 줄 상자 =
    /// 1.3 cell인 상자에서는 `cellHeight − ascent`와 같다 (#223 전의 정의).
    public var descent: CGFloat {
        lineHeight - baseline
            - HwpRenderTuning.Text.msWordBaselineMarginCellRatio * cellHeight
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

    /// OS/2 `ulUnicodeRange2`의 CJK 블록 비트 (Unicode range 48–59·61 — CJK 기호부터
    /// CJK 통합 한자까지의 연속 구간과 CJK 획/CJK 호환 한자). 60(사용자 영역)·62(알파벳
    /// 표현형)·63(아랍 표현형 A)은 한글의 판정에 들지 않는다 — 62·63만 켠 Courier New·
    /// Times New Roman·Arial·Tahoma와 60·62만 남긴 Menlo 사본이 그 밖 갈래다. 47 아래의
    /// 비트는 라틴·기호 블록이라 판정에 들지 않는다(Helvetica·Monaco·Lucida Grande가
    /// 32–47을 갖고도 그 밖).
    static let cjkUnicodeRange2Mask: UInt32 = {
        var mask: UInt32 = 0
        for bit in 48 ... 59 {
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
        return parse(
            os2: CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?,
            hhea: CTFontCopyTable(font, CTFontTableTag(kCTFontTableHhea), []) as Data?,
            unitsPerEm: unitsPerEm
        ) ?? fallback(from: font)
    }

    /// 표 바이트에서 줄 상자를 푼다 — OS/2가 있으면 win 지표(+ hhea lineGap), 없으면 hhea
    /// ascent·descent, 둘 다 못 읽으면 nil. 글꼴 없이 합성 표로 테스트하려고 갈라 두었다
    /// (PR 리뷰: KhmerMN의 win 합 UInt16 넘침, hhea descent −32768의 Int16 절댓값 트랩).
    static func parse(os2: Data?, hhea: Data?, unitsPerEm: CGFloat) -> HwpMsWordLineBox? {
        // hhea: ascent 4·descent 6·lineGap 8 (FWORD)
        let lineGap = hhea.flatMap { $0.int16(at: 8) }.map { CGFloat($0) / unitsPerEm } ?? 0
        if let os2,
           let winAscent = os2.uint16(at: 74), let winDescent = os2.uint16(at: 76),
           Int(winAscent) + Int(winDescent) > 0
        {
            // 두 값은 UInt16이라 Int로 더한다 — KhmerMN처럼 합이 65,535를 넘는 글꼴이 있다.
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
            // FWORD는 Int16 — −32768의 절댓값은 Int16에 없으므로 Int로 넓힌 뒤 취한다.
            return HwpMsWordLineBox(
                winAscent: CGFloat(ascent) / unitsPerEm,
                winDescent: CGFloat(abs(Int(descent))) / unitsPerEm,
                lineGap: lineGap,
                isCJK: false
            )
        }
        return nil
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

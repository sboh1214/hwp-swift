import CoreText
import Foundation

/// 글꼴의 짝 커닝·위치 조정이 닿을 수 있는 글리프 집합 (#260) — 자간을 kern에 실어도 tracking과
/// 결과가 같은지 가른다 (`HwpLetterSpacing.segments`).
///
/// CoreText는 `kCTKernAttributeName`이 **정확히 0**인 글자에서 글꼴의 커닝을 끄고, 0이 아니면 켠다
/// (속성이 없을 때도 켠다). 짝 커닝은 **두 글자가 모두** kern ≠ 0일 때만 걸린다 — 실측(Times New
/// Roman·함초롬바탕·Arial 20pt `xAVx`): A·V 중 하나만 kern 1이면 `AV` 짝 커닝이 없고, 둘 다 0이 아니면
/// 값이 달라도(1·2, −1·−2, −1·1) 걸린다. tracking은 kern이 0인 글자에 실려도 커닝을 켜지 않는다.
/// 그래서 **이 집합에 든 글리프만 kern을 0으로 두면**(자간은 tracking으로) 나머지 글리프의 자간을
/// kern에 실어도 어떤 커닝도 켜지지 않는다 — 조정이 걸리는 글리프는 반드시 이 집합에 든다.
///
/// 집합은 보수적인 상위집합이다 (넓을수록 tracking이 늘어 느려질 뿐 결과는 같다):
/// - `kern` 표 형식 0의 **왼쪽** 글리프 (값 0이 아닌 짝). 다른 형식은 해석하지 않고 전체로 본다.
/// - GPOS의 **모든** 단일 조정(유형 1)·짝 조정(유형 2, 첫 글리프)·필기체 연결(유형 3) 룩업의 커버리지
///   (확장 유형 9는 풀어서 본다). 기능 목록(`kern`·`dist`)을 따라가지 않으므로 꺼진 기능(`halt` 등)의
///   커버리지까지 들어간다. 문맥 룩업(유형 7·8)은 중첩 룩업으로 조정하는데 그 룩업도 목록에 있어 이미
///   든다. 표시 위치 조정(유형 4–6, 결합 부호 붙이기)은 kern 0에서도 걸리므로(실측: Helvetica·Menlo·
///   Apple SD 산돌고딕 Neo의 `x` + U+0301이 kern 0·tracking·kern에서 같은 자리) 넣지 않는다.
/// - GSUB의 합자·문맥·역문맥 치환(유형 4·5·6·8, 확장 유형 7은 풀어서) 룩업의 **시작 글리프** 커버리지 —
///   tracking은 선택 합자와 일부 문맥 형태를 끄는데 kern은 끄지 않으므로, 치환이 시작될 수 있는 글리프도
///   tracking으로 보내야 두 운반 속성의 글리프가 같다.
/// - AAT `kerx`·`morx`·`mort` 표가 있으면 전체로 본다(해석하지 않는다 — Menlo·Helvetica가 그렇다).
///
/// 실측 크기(2026-10-08, 설치 글꼴 934종 fontTools 대조 일치): Apple SD 산돌고딕 Neo 143글리프(라틴 66·
/// `〃`·`dlig` 합자의 첫 음절 `주`), 함초롬바탕 668(라틴 13, 나머지는 데바나가리 등), 함초롬돋움 714(라틴 63),
/// AppleMyungjo 0, Times New Roman 164(라틴 19)·Arial 170(라틴 19). 한글 음절·한자는 한글 글꼴에서 거의
/// 들지 않지만 예외가 있다 — Apple SD 산돌고딕 Neo의 `주`, 일본어 글꼴 Hiragino Sans의 한자 164자(GPOS
/// `palt` 계열 단일 조정). 그런 글리프는 tracking으로 실려 결과는 같고 조판만 느리다.
enum HwpKerningCoverage {
    /// 글리프 집합 — 비트 하나가 글리프 하나. `nil`인 자리(`glyphs(of:)`)는 "모든 글리프".
    struct GlyphSet: Equatable {
        private(set) var words: [UInt64] = []

        var isEmpty: Bool {
            words.allSatisfy { $0 == 0 }
        }

        func contains(_ glyph: CGGlyph) -> Bool {
            let index = Int(glyph) >> 6
            return index < words.count && words[index] & (1 << (UInt64(glyph) & 63)) != 0
        }

        mutating func insert(_ glyph: UInt16) {
            let index = Int(glyph) >> 6
            if index >= words.count {
                words += [UInt64](repeating: 0, count: index + 1 - words.count)
            }
            words[index] |= 1 << (UInt64(glyph) & 63)
        }

        /// 범위를 낱말(64글리프) 단위로 채운다 — 0…65535 범위도 1,024번이다.
        mutating func insert(from start: UInt16, through end: UInt16) {
            guard start <= end else { return }
            let first = Int(start) >> 6
            let last = Int(end) >> 6
            if last >= words.count {
                words += [UInt64](repeating: 0, count: last + 1 - words.count)
            }
            for index in first ... last {
                let low = index == first ? Int(start) & 63 : 0
                let high = index == last ? Int(end) & 63 : 63
                let width = high - low + 1
                let bits: UInt64 = width == 64 ? ~0 : (1 << UInt64(width)) - 1
                words[index] |= bits << UInt64(low)
            }
        }
    }

    /// 표 해석 상태 — 이미 본 룩업·부분표·커버리지는 다시 보지 않고(OpenType은 부분표 공유를 허용해
    /// 조작된 표가 같은 자리를 수만 번 가리킬 수 있다 — 그대로 훑으면 154바이트 GPOS가 0.1초, 128KB면
    /// 수십 시간이다), 읽은 항목 수가 `maximumWork`를 넘으면 해석을 포기한다. 포기는 nil(모든 글리프)이라
    /// 자간이 tracking으로 실릴 뿐 결과는 같다. 표마다 하나씩 쓴다(오프셋이 표 안 값이라서).
    struct Walk {
        static let maximumWork = 1 << 20

        var set: GlyphSet
        private var visited = Set<Int>()
        private var work = 0

        init(set: GlyphSet = GlyphSet()) {
            self.set = set
        }

        /// 항목 `count`개를 읽는다 — 예산 안이면 true.
        mutating func spend(_ count: Int) -> Bool {
            work += max(0, count)
            return work <= Self.maximumWork
        }

        /// `kind`(0 룩업·1 부분표·2 커버리지)의 `offset`을 처음 보는가. 부분표는 `type`(확장을 푼
        /// 룩업 유형)도 열쇠에 든다 — OpenType은 룩업끼리 부분표 자리를 나눠 쓸 수 있어, 건너뛰는
        /// 유형(GSUB 1–3·GPOS 4–8)의 룩업이 먼저 같은 바이트를 방문하면 그 자리를 모으는 유형으로 읽는
        /// 룩업이 건너뛰어져 커버리지가 빠졌다 (#260 리뷰 — 결과가 룩업 순서에 달렸다).
        mutating func firstVisit(_ offset: Int, kind: Int, type: UInt16 = 0) -> Bool {
            visited.insert((offset << 4 | Int(type & 0xF)) << 2 | kind).inserted
        }
    }

    /// `font`의 커닝 관여 글리프. `nil`이면 해석할 수 없어 모든 글리프로 본다.
    ///
    /// 글꼴 표는 크기·행렬과 무관하므로 PostScript 이름(+ 파일 URL)으로 프로세스 전역에 캐시한다 —
    /// 문서마다 다른 값이 아니다(`HwpTextAttributeCache`의 문서 단위 소유와 다르다).
    static func glyphs(of font: CTFont) -> GlyphSet? {
        FontCache.shared.glyphs(of: font)
    }

    /// 테스트 전용 관측 지점 — 전역 캐시 조회 수(`glyphs(of:)` 호출 수). 열쇠를 만드는 조회도 공짜가
    /// 아니라(PostScript 이름·파일 경로 복사) chunk마다 이 길을 다시 타면 안 된다
    /// (`HwpTextAttributeCache.kerningCoverage`가 문서 안에서 한 번으로 줄인다).
    static var lookupCount: Int {
        FontCache.shared.lookupCount
    }

    /// 표를 해석한 집합 — 없는 표는 nil. 해석 못 하는 형식·잘린 표면 nil(모든 글리프).
    static func parse(
        kern: Data?, kerx: Data?, gpos: Data?, gsub: Data? = nil, morx: Data? = nil
    ) -> GlyphSet? {
        if kerx != nil || morx != nil {
            return nil
        }
        var set = GlyphSet()
        if let kern {
            var walk = Walk(set: set)
            guard parseKern(Reader(kern), into: &walk) else { return nil }
            set = walk.set
        }
        if let gpos {
            var walk = Walk(set: set)
            guard parseLookups(
                Reader(gpos), extensionType: 9, collect: [1, 2, 3], skip: 4 ... 8, into: &walk
            )
            else { return nil }
            set = walk.set
        }
        if let gsub {
            var walk = Walk(set: set)
            guard parseLookups(
                Reader(gsub), extensionType: 7, collect: [4, 5, 6, 8], skip: 1 ... 3, into: &walk
            )
            else { return nil }
            set = walk.set
        }
        return set
    }

    // MARK: - 캐시

    /// 글꼴별 집합 캐시 — 표 해석은 lock 밖에서 한다(경합하면 같은 글꼴을 두 번 해석할 수 있지만
    /// 순수 함수라 결과가 같다 — `HwpTextAttributeCache`와 같은 절충).
    private final class FontCache: @unchecked Sendable {
        static let shared = FontCache()

        /// 상한 — 넘으면 삽입만 멈춘다(`HwpTextAttributeCache`와 같은 절단). 한 프로세스가 쓰는 글꼴
        /// 수는 수십이다.
        private static let maximumEntries = 512

        private struct Entry {
            let set: GlyphSet?
        }

        private var storage: [String: Entry] = [:]
        private var lookups = 0
        private let lock = NSLock()

        var lookupCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return lookups
        }

        func glyphs(of font: CTFont) -> GlyphSet? {
            let key = Self.key(of: font)
            lock.lock()
            lookups += 1
            if let cached = storage[key] {
                lock.unlock()
                return cached.set
            }
            lock.unlock()
            let table = { (tag: Int) in CTFontCopyTable(font, CTFontTableTag(tag), []) as Data? }
            let set = parse(
                kern: table(kCTFontTableKern), kerx: table(kCTFontTableKerx),
                gpos: table(kCTFontTableGPOS), gsub: table(kCTFontTableGSUB),
                morx: table(kCTFontTableMorx) ?? table(kCTFontTableMort)
            )
            lock.lock()
            if storage.count < Self.maximumEntries {
                storage[key] = Entry(set: set)
            }
            lock.unlock()
            return set
        }

        /// PostScript 이름 + 파일 경로 — 같은 이름의 다른 글꼴 파일을 섞지 않는다.
        private static func key(of font: CTFont) -> String {
            let name = CTFontCopyPostScriptName(font) as String
            let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL
            return name + "\u{0}" + (url?.path ?? "")
        }
    }

    // MARK: - 표 해석

    /// 큰 끝 바이트 읽기 — 범위를 넘으면 nil.
    struct Reader {
        let data: Data

        init(_ data: Data) {
            self.data = data
        }

        func u16(_ offset: Int) -> UInt16? {
            guard offset >= 0, offset + 2 <= data.count else { return nil }
            let start = data.startIndex + offset
            return UInt16(data[start]) << 8 | UInt16(data[start + 1])
        }

        func u32(_ offset: Int) -> UInt32? {
            guard let high = u16(offset), let low = u16(offset + 2) else { return nil }
            return UInt32(high) << 16 | UInt32(low)
        }
    }

    /// `kern` 표 — 마이크로소프트 판(버전 0, 16비트 머리)과 애플 판(버전 1.0, 32비트 머리)의 형식 0
    /// 부분표만 해석한다. 다음 부분표 자리는 애플 판이 32비트 길이 필드로, 마이크로소프트 판이 짝 수로
    /// 정한다 — 마이크로소프트 판의 16비트 길이 필드는 큰 표에서 넘치고, 애플 판은 부분표 끝에 채움
    /// 바이트를 둘 수 있다(Hoefler Text BlackItalic — 짝 수로 재면 둘째 부분표 머리를 놓친다).
    static func parseKern(_ table: Reader, into walk: inout Walk) -> Bool {
        guard let version = table.u16(0) else { return false }
        let apple = version == 1
        guard version == 0 || apple else { return false }
        guard let tableCount = apple ? table.u32(4).map(Int.init) : table.u16(2).map(Int.init)
        else { return false }
        var offset = apple ? 8 : 4
        for _ in 0 ..< tableCount {
            // 부분표 머리: MS = 버전·길이·coverage(각 2바이트), 애플 = 길이(4)·coverage(2)·tuple(2).
            // 둘 다 coverage가 +4에 있고 형식은 MS가 위 바이트, 애플이 아래 바이트다.
            let headerLength = apple ? 8 : 6
            guard let coverage = table.u16(offset + 4) else { return false }
            let format = apple ? coverage & 0xFF : coverage >> 8
            guard format == 0, let pairCount = table.u16(offset + headerLength).map(Int.init),
                  walk.spend(1 + pairCount)
            else { return false }
            let pairs = offset + headerLength + 8
            for pair in 0 ..< pairCount {
                guard let left = table.u16(pairs + pair * 6),
                      let value = table.u16(pairs + pair * 6 + 4)
                else { return false }
                if value != 0 {
                    walk.set.insert(left)
                }
            }
            if apple {
                // 길이가 짝 배열보다 짧으면 부분표가 겹친다 — 같은 짝을 다시 훑게 하는 조작 표다.
                guard let length = table.u32(offset).map(Int.init),
                      length >= headerLength + 8 + pairCount * 6
                else { return false }
                offset += length
            } else {
                offset = pairs + pairCount * 6
            }
        }
        return true
    }

    /// GPOS·GSUB — 룩업 목록의 모든 룩업을 훑어 `collect` 유형 부분표의 커버리지(형식 뒤 첫 오프셋)를
    /// 담는다. 확장 유형(GPOS 9·GSUB 7)은 풀어서 보고, `skip` 유형은 건너뛰며, 그 밖의 유형은 해석하지
    /// 못한 것으로 본다. 문맥 유형(GSUB 5·6) 형식 3은 첫 입력 커버리지가 다른 자리에 있어 따로 읽는다.
    static func parseLookups(
        _ table: Reader, extensionType: UInt16, collect: Set<UInt16>, skip: ClosedRange<UInt16>,
        into walk: inout Walk
    ) -> Bool {
        guard let listOffset = table.u16(8).map(Int.init) else { return false }
        guard listOffset != 0 else { return true }
        guard let lookupCount = table.u16(listOffset).map(Int.init), walk.spend(lookupCount)
        else { return false }
        for lookup in 0 ..< lookupCount {
            guard let relative = table.u16(listOffset + 2 + lookup * 2).map(Int.init)
            else { return false }
            let lookupStart = listOffset + relative
            guard walk.firstVisit(lookupStart, kind: 0) else { continue }
            guard let type = table.u16(lookupStart),
                  let subtableCount = table.u16(lookupStart + 4).map(Int.init),
                  walk.spend(subtableCount)
            else { return false }
            for subtable in 0 ..< subtableCount {
                guard let subtableOffset = table.u16(lookupStart + 6 + subtable * 2).map(Int.init)
                else { return false }
                var start = lookupStart + subtableOffset
                var subtableType = type
                if subtableType == extensionType {
                    guard let wrapped = table.u16(start + 2),
                          let extensionOffset = table.u32(start + 4).map(Int.init)
                    else { return false }
                    subtableType = wrapped
                    start += extensionOffset
                }
                guard walk.firstVisit(start, kind: 1, type: subtableType) else { continue }
                if collect.contains(subtableType) {
                    guard let format = table.u16(start),
                          let coverage = coverageOffset(
                              table, subtable: start, type: subtableType, format: format
                          ),
                          parseCoverage(table, at: start + coverage, into: &walk)
                    else { return false }
                } else if !skip.contains(subtableType) {
                    return false
                }
            }
        }
        return true
    }

    /// 부분표의 (첫) 커버리지 오프셋. 대부분 형식 뒤 첫 필드이고, 문맥 형식 3만 다르다 — GSUB 5
    /// 형식 3은 입력 수·치환 수 뒤 커버리지 배열, GSUB 6 형식 3은 앞 문맥 커버리지 배열 뒤 입력 수와
    /// 입력 커버리지 배열이다.
    private static func coverageOffset(
        _ table: Reader, subtable start: Int, type: UInt16, format: UInt16
    ) -> Int? {
        switch (type, format) {
        case (5, 3):
            return table.u16(start + 6).map(Int.init)
        case (6, 3):
            guard let backtrack = table.u16(start + 2).map(Int.init) else { return nil }
            let inputCount = start + 4 + backtrack * 2
            guard let count = table.u16(inputCount), count > 0 else { return nil }
            return table.u16(inputCount + 2).map(Int.init)
        default:
            return table.u16(start + 2).map(Int.init)
        }
    }

    /// OpenType 커버리지 표 — 형식 1(글리프 배열)·2(범위 배열).
    static func parseCoverage(_ table: Reader, at offset: Int, into walk: inout Walk) -> Bool {
        guard walk.firstVisit(offset, kind: 2) else { return true }
        guard let format = table.u16(offset), let count = table.u16(offset + 2).map(Int.init),
              walk.spend(count)
        else { return false }
        switch format {
        case 1:
            for index in 0 ..< count {
                guard let glyph = table.u16(offset + 4 + index * 2) else { return false }
                walk.set.insert(glyph)
            }
        case 2:
            for index in 0 ..< count {
                let record = offset + 4 + index * 6
                guard let start = table.u16(record), let end = table.u16(record + 2)
                else { return false }
                // 범위 하나가 채우는 낱말(64글리프) 수만큼 예산을 쓴다 — 기록 하나를 1로 세면 0…65535 범위
                // 기록이 1,024번 쓰기를 하면서 1만 써, 조작된 표가 예산의 1,024배 일을 시킨다 (#260 리뷰).
                if start <= end {
                    guard walk.spend(Int(end) >> 6 - Int(start) >> 6) else { return false }
                }
                walk.set.insert(from: start, through: end)
            }
        default:
            return false
        }
        return true
    }
}

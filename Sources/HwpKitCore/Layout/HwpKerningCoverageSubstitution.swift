import Foundation

// MARK: - GSUB 단일·다중·대체 치환의 입력 (#260 리뷰)

extension HwpKerningCoverage {
    /// GSUB 단일·다중·대체 치환(유형 1–3) 규칙 — 입력 글리프 하나와 그 결과 글리프들. `inputs[i]`의 결과는
    /// `outputs[ends[i - 1] ..< ends[i]]`다(첫 규칙은 0부터).
    struct SubstitutionRules {
        private(set) var inputs: [UInt16] = []
        private(set) var ends: [Int] = []
        private(set) var outputs: [UInt16] = []

        /// 결과 하나짜리 규칙(단일 치환).
        mutating func append(_ input: UInt16, result: UInt16) {
            outputs.append(result)
            close(input)
        }

        /// 지금까지 `appendResult`로 쌓은 결과를 `input`의 규칙으로 닫는다.
        mutating func close(_ input: UInt16) {
            inputs.append(input)
            ends.append(outputs.count)
        }

        mutating func appendResult(_ result: UInt16) {
            outputs.append(result)
        }

        /// 결과 글리프마다 그 글리프를 결과로 갖는 규칙들 — `rules[starts[g] ..< starts[g + 1]]`가 글리프 `g`의
        /// 규칙 번호다(결과 → 규칙 역색인). 결과 하나를 한 번씩만 본다.
        func rulesByResult() -> (starts: [Int32], rules: [Int32]) {
            var starts = [Int32](repeating: 0, count: 65537)
            for output in outputs {
                starts[Int(output) + 1] += 1
            }
            for glyph in 0 ..< 65536 {
                starts[glyph + 1] += starts[glyph]
            }
            var cursor = starts
            var rules = [Int32](repeating: 0, count: outputs.count)
            var rule = 0
            for (position, output) in outputs.enumerated() {
                while position >= ends[rule] {
                    rule += 1
                }
                rules[Int(cursor[Int(output)])] = Int32(rule)
                cursor[Int(output)] += 1
            }
            return (starts, rules)
        }
    }

    /// 치환 결과가 집합에 드는 입력 글리프를 `walk.set`에 더한다 — 더할 것이 없을 때까지(치환이 이어지는
    /// 사슬). 해석할 수 없으면 false(모든 글리프).
    ///
    /// 집합은 GPOS·`kern`·GSUB 시작 글리프의 커버리지로 모으는데, 그 커버리지는 **치환 뒤** 글리프를 가리키고
    /// 자간 운반 속성은 **치환 전** 글리프(`CTFontGetGlyphsForCharacters`)로 고른다. 치환이 집합 밖 글리프를
    /// 집합 안 글리프로 바꾸면 그 자리는 kern(≠ 0)을 지닌 채 조정을 받게 된다 — tracking만 쓴 조판과 갈린다
    /// (#260 리뷰 실측: NotoNastaliqUrdu-Bold 20pt 기타 언어 자간 −20% `لمْ`에서 `ل`은 집합 밖이라 kern인데
    /// 어두 형태로 바뀐 글리프가 필기체 연결(GPOS 유형 3) 커버리지에 들어, glyph 410의 y가 tracking만으로는
    /// 11.88, 섞으면 0이었다). 그래서 그런 입력을 집합에 넣는다. 입력을 모두 넣으면 결과는 같지만 Apple SD
    /// 산돌고딕 Neo의 `가`·`이`·`하`·`다` 같은 흔한 음절 78자(결과가 집합 밖인 단일 치환)와 라틴 전체가
    /// tracking으로 가 조판이 느려진다 — 결과가 집합에 드는 입력만 넣는다.
    static func closeOverSubstitutions(_ table: Reader, into walk: inout Walk) -> Bool {
        var traversal = Walk()
        var rules = SubstitutionRules()
        let parsed = forEachSubtable(
            table, extensionType: 7, walk: &traversal
        ) { type, start, traversal in
            switch type {
            case 1 ... 3:
                parseSubstitution(table, type: type, at: start, walk: &traversal, into: &rules)
            default:
                (4 ... 8).contains(type)
            }
        }
        guard parsed else { return false }
        // 집합에 든 글리프에서 거꾸로 — 그 글리프를 결과로 갖는 규칙의 입력을 넣고, 새로 든 입력을 다시 따른다.
        // 결과(역색인 항목)마다 한 번씩만 보므로 일이 결과 수에 비례한다. 패스마다 모든 규칙의 결과를 다시 훑으면
        // 의존 사슬 길이 × 결과 수라, 결과가 긴 다중 치환과 고리 1,000개짜리 사슬을 섞은 조작 표가 예산 안에서
        // 결과를 수억 번 검사했다 (#260 PR 리뷰 실측: 2MB GSUB 디버그 빌드 137초).
        guard walk.spend(rules.inputs.count + rules.outputs.count) else { return false }
        let index = rules.rulesByResult()
        var pending = walk.set.members
        while let glyph = pending.popLast() {
            for entry in index.starts[Int(glyph)] ..< index.starts[Int(glyph) + 1] {
                let input = rules.inputs[Int(index.rules[Int(entry)])]
                if !walk.set.contains(input) {
                    walk.set.insert(input)
                    pending.append(input)
                }
            }
        }
        return true
    }

    /// 단일(형식 1 델타·형식 2 배열)·다중·대체 치환 부분표 하나의 규칙.
    private static func parseSubstitution(
        _ table: Reader, type: UInt16, at start: Int, walk: inout Walk,
        into rules: inout SubstitutionRules
    ) -> Bool {
        guard let format = table.u16(start), let offset = table.u16(start + 2).map(Int.init)
        else { return false }
        let coverage = start + offset
        switch (type, format) {
        case (1, 1):
            guard let delta = table.u16(start + 4).map({ Int(Int16(bitPattern: $0)) })
            else { return false }
            return forEachCoveredGlyph(table, at: coverage, walk: &walk) { glyph, _, _ in
                rules.append(glyph, result: UInt16(truncatingIfNeeded: Int(glyph) + delta))
                return true
            }
        case (1, 2):
            guard let count = table.u16(start + 4).map(Int.init) else { return false }
            return forEachCoveredGlyph(table, at: coverage, walk: &walk) { glyph, index, _ in
                guard index < count, let result = table.u16(start + 6 + index * 2)
                else { return false }
                rules.append(glyph, result: result)
                return true
            }
        case (2, 1), (3, 1):
            return parseSequenceSubstitution(
                table, at: start, coverage: coverage, walk: &walk, into: &rules
            )
        default:
            return false
        }
    }

    /// 다중 치환(순서열)·대체 치환(대체 집합) 형식 1 — 둘은 같은 꼴이다: 수·오프셋 배열, 각 표는 수·글리프 배열.
    private static func parseSequenceSubstitution(
        _ table: Reader, at start: Int, coverage: Int, walk: inout Walk,
        into rules: inout SubstitutionRules
    ) -> Bool {
        guard let count = table.u16(start + 4).map(Int.init) else { return false }
        return forEachCoveredGlyph(table, at: coverage, walk: &walk) { glyph, index, walk in
            guard index < count,
                  let sequence = table.u16(start + 6 + index * 2).map({ start + Int($0) }),
                  let length = table.u16(sequence).map(Int.init), walk.spend(length)
            else { return false }
            for item in 0 ..< length {
                guard let result = table.u16(sequence + 2 + item * 2) else { return false }
                rules.appendResult(result)
            }
            rules.close(glyph)
            return true
        }
    }

    /// 커버리지 표의 글리프를 커버리지 순번과 함께 차례로 부른다 — 형식 1(글리프 배열)·2(범위 배열, 범위마다
    /// 시작 순번). 글리프마다 예산을 쓴다.
    private static func forEachCoveredGlyph(
        _ table: Reader, at offset: Int, walk: inout Walk,
        _ body: (UInt16, Int, inout Walk) -> Bool
    ) -> Bool {
        guard let format = table.u16(offset), let count = table.u16(offset + 2).map(Int.init),
              walk.spend(count)
        else { return false }
        switch format {
        case 1:
            for index in 0 ..< count {
                guard let glyph = table.u16(offset + 4 + index * 2), body(glyph, index, &walk)
                else { return false }
            }
        case 2:
            for record in 0 ..< count {
                guard forEachRangeGlyph(table, record: offset + 4 + record * 6, walk: &walk, body)
                else { return false }
            }
        default:
            return false
        }
        return true
    }

    /// 커버리지 형식 2의 범위 기록 하나(시작·끝 글리프, 시작 순번) — 범위 글리프 수만큼 예산을 쓴다.
    private static func forEachRangeGlyph(
        _ table: Reader, record: Int, walk: inout Walk,
        _ body: (UInt16, Int, inout Walk) -> Bool
    ) -> Bool {
        guard let first = table.u16(record), let last = table.u16(record + 2),
              let startIndex = table.u16(record + 4).map(Int.init)
        else { return false }
        guard first <= last else { return true }
        guard walk.spend(Int(last) - Int(first) + 1) else { return false }
        for glyph in first ... last {
            guard body(glyph, startIndex + Int(glyph - first), &walk) else { return false }
        }
        return true
    }
}

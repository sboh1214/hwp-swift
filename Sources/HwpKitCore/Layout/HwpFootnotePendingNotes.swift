import CoreGraphics
import CoreHwp
import Foundation

// 대기 각주 목록과 지연 측정 — 배치 산식(`HwpFootnoteLayout.swift`)과 갈라 둔다 (그 파일이
// SwiftLint file_length 상한 700줄에 닿았다). 예약·배치가 공유하는 측정 자체는
// `HwpFootnoteNoteMeasurement.swift`.

// MARK: - 대기 각주 목록

extension HwpFootnoteLayout {
    /// 대기 각주 목록 — 입력 저장소의 **슬라이스**와, 그 첫 항목을 대신하는 **이월 조각 입력**
    /// (#165 리뷰). 쪽마다 남은 각주를 새 배열로 뜨면 그 복사·retain이 쪽 수 × N이라 저장소는
    /// 슬라이스로 나르고, 쪽 끝에서 나뉜 문단의 이월 입력은 꼬리를 복사해 앞에 붙이는 대신
    /// `head`로 따로 든다 — 나뉘는 문단은 언제나 그 쪽에 실린 몫 바로 다음, 즉 남은 목록의 첫
    /// 항목이므로 첫 항목만 대신하면 된다. 배열은 공개 경계(`Placement`)에서만 만든다.
    struct PendingNotes: RandomAccessCollection, ExpressibleByArrayLiteral {
        private(set) var storage: ArraySlice<Input>
        /// 저장소 첫 항목을 대신하는 이월 조각 입력 — 저장소가 비면 뜻이 없다.
        private(set) var head: Input?

        init() {
            storage = []
            head = nil
        }

        init(_ storage: ArraySlice<Input>, head: Input? = nil) {
            self.storage = storage
            self.head = storage.isEmpty ? nil : head
        }

        init(arrayLiteral elements: Input...) {
            self.init(elements[...])
        }

        var startIndex: Int {
            0
        }

        var endIndex: Int {
            storage.count
        }

        subscript(position: Int) -> Input {
            if position == 0, let head {
                return head
            }
            return storage[storage.startIndex + position]
        }

        /// `start`부터의 남은 목록 — 저장소는 같은 슬라이스고 머리는 `start == 0`일 때만 남는다.
        func remaining(from start: Int) -> PendingNotes {
            let clamped = Swift.min(Swift.max(0, start), storage.count)
            return PendingNotes(
                storage[(storage.startIndex + clamped)...], head: clamped == 0 ? head : nil
            )
        }

        /// 첫 항목을 `input`으로 대신한 사본 — 꼬리는 복사하지 않는다.
        func replacingFirst(with input: Input) -> PendingNotes {
            PendingNotes(storage, head: input)
        }

        mutating func append(_ input: Input) {
            storage.append(input)
        }

        mutating func removeAll() {
            storage = []
            head = nil
        }

        /// 공개 경계용 배열
        var array: [Input] {
            Array(self)
        }
    }
}

// MARK: - 문단 측정 + 개체 수집

extension HwpFootnoteLayout {
    /// 이 쪽에 실을 후보 각주들의 **지연** 측정 (#165 리뷰). 쪽마다 대기 각주 전부를 재면
    /// 독립 각주 N개가 쪽마다 몇 개씩만 실리는 이월에서 쪽 수 × N의 CT 조판이 된다 (실측,
    /// 디버그 빌드: 55줄 각주 100개·101쪽 41.5s, 200개 165.4s — 2배에 4배). 스택 계획은
    /// 순서대로 보다가 처음 안 들어가는 각주에서 멈추므로, 그때까지 본 각주만 재면 전체
    /// 일이 각주 수에 비례한다. 잰 값은 이 쪽 안에서만 보관한다 — 이월은 `Input`이 나른다.
    ///
    /// 입력은 대기 목록(`PendingNotes`)을 그대로 든다 (#165 리뷰): 쪽마다 대기 각주를 새
    /// 배열로 뜨면 (`Array(suffix)`) 그 복사·retain 몫이 다시 쪽 수 × N이다 — 이월
    /// (`inputs(from:)`)도 같은 저장소라 복사가 없다. 잰 값은 오프셋별 사전이라 안 잰 각주엔
    /// 비용이 없다. 줄 캐시·개체 판정은 **재지 않고도** 준다 (`cacheLines(at:)`·
    /// `carriesObjects(at:)`) — 분할 지점 탐색이 그것만 필요한데 측정을 거치면 문단 N개짜리
    /// 각주가 문단마다 쪽을 넘길 때 쪽 수 × N의 CT 조판이다.
    ///
    /// 각주 모양은 입력이 **각인**해 온 것을 쓴다 (`Input.measuredShape` — 페이지네이터는
    /// 수집 시점에, 공개 API 입력은 처음 잴 때 이 쪽의 모양으로). 재지 않고 이월된 공개 API
    /// 입력은 다음 호출의 모양으로 잰다.
    final class MeasuredNotes {
        /// 이 쪽의 후보 입력 — 호출자의 대기 목록 그대로.
        let inputs: PendingNotes
        private let footnoteShape: CoreHwp.HwpFootnoteShape?
        private var cache: [Int: MeasuredFootnote] = [:]
        private var cacheLinesByOffset: [Int: [HwpFootnoteCacheLine]?] = [:]
        private var carrying: [Int: Bool] = [:]
        private let measure: (Input, Bool) -> NoteMeasurement

        init(
            inputs: PendingNotes,
            footnoteShape: CoreHwp.HwpFootnoteShape?,
            measure: @escaping (Input, Bool) -> NoteMeasurement
        ) {
            self.inputs = inputs
            self.footnoteShape = footnoteShape
            self.measure = measure
        }

        var count: Int {
            inputs.count
        }

        func input(at offset: Int) -> Input {
            inputs[offset]
        }

        func noteId(at offset: Int) -> Int {
            inputs[offset].noteId
        }

        /// `offset`의 각주를 (처음이면) 재서 준다 — 아직 모양을 각인하지 않은 입력은 이 쪽의
        /// 모양으로 확정한다 (기본 모양 nil도 확정, `Input.measuredShape`).
        subscript(offset: Int) -> MeasuredFootnote {
            if let measured = cache[offset] {
                return measured
            }
            let raw = inputs[offset]
            let input = raw.measuredShape == nil ? raw.withMeasuredShape(footnoteShape) : raw
            let measured = MeasuredFootnote(
                input: input, measurement: measure(input, carriesObjects(at: offset))
            )
            cache[offset] = measured
            return measured
        }

        /// `offset` 문단의 줄 캐시 — 측정(`measureNote`)과 같은 출처(나른 원본 조판 또는
        /// 문단의 줄 세그먼트)라 값이 같고, CT 조판 없이 준다.
        func cacheLines(at offset: Int) -> [HwpFootnoteCacheLine]? {
            if let known = cacheLinesByOffset[offset] {
                return known
            }
            let input = inputs[offset]
            let lines = input.sourceLayout?.cacheLines ?? HwpFootnoteCacheLines.lines(of: input.paragraph)
            cacheLinesByOffset[offset] = lines
            return lines
        }

        /// `start`부터의 입력 — 같은 저장소라 복사가 없다.
        func inputs(from start: Int) -> PendingNotes {
            inputs.remaining(from: start)
        }

        /// 개체 판정은 **각주 단위**다 (#165 리뷰) — 분할 금지와 CT 높이 보존의 범위를
        /// 맞춘다. 문단 단위로 보면 개체 없는 앞 문단만 캐시 합으로 줄어 뒤 문단의 그림이
        /// 그 문단의 마지막 글줄 위로 올라온다. 술어는 **수집 대상 전체**를 본다
        /// (`hasCollectibleObject`) — 하한 술어로 보면 글 앞으로 그림이 빠져 예약과 갈린다.
        /// 같은 각주의 문단은 잇닿아 있으므로 **그 이웃만** 훑고 각주별로 한 번만 판정한다
        /// — 전체를 훑으면 쪽에 실리는 각주 수 × N이다. 측정(`NoteMeasurement.carriesObjects`)
        /// 과 같은 답이다: 수집된 개체는 모두 이 술어의 관문을 지난 것이다.
        func carriesObjects(at offset: Int) -> Bool {
            let target = noteId(at: offset)
            if let known = carrying[target] {
                return known
            }
            var carries = false
            var low = offset
            while low > 0, noteId(at: low - 1) == target {
                low -= 1
            }
            var index = low
            while index < inputs.count, noteId(at: index) == target, !carries {
                carries = HwpParagraphObjectCollector.hasCollectibleObject(
                    in: inputs[index].paragraph, collectsTextboxes: true, collectsTables: true
                )
                index += 1
            }
            carrying[target] = carries
            return carries
        }
    }

    /// 후보 각주들의 지연 측정기 — 실제 측정은 `measureNote` 한 함수다 (예약과 공유).
    /// 각주 모양은 **처음 잰 것**을 들고 간다 (#165 리뷰) — 인자는 아직 각인하지 않은 입력의
    /// 첫 측정에만 쓰이고, 각인해 두면 이월 입력이 스스로 그 모양을 나른다. 기본 모양(nil)으로
    /// 잰 것도 확정이라 다음 쪽의 인자를 다시 채택하지 않는다.
    func measuredNotes(
        _ footnotes: PendingNotes,
        index: HwpIndex,
        width: CGFloat,
        footnoteShape: CoreHwp.HwpFootnoteShape? = nil,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> MeasuredNotes {
        MeasuredNotes(inputs: footnotes, footnoteShape: footnoteShape) { input, noteCarriesObjects in
            self.measureNote(
                input.paragraph,
                number: input.number,
                width: width,
                index: index,
                footnoteShape: input.measuredShape?.footnoteShape,
                // 수집 시점 해석기를 우선한다 — 인자는 그것이 없는 호출
                // (테스트·직접 배치) 의 폴백이다 (R44 #1).
                sizeResolver: input.sizeResolver ?? sizeResolver,
                numbering: input.numbering,
                placedLineCount: input.placedLineCount,
                placedLength: input.placedLength,
                noteCarriesObjects: noteCarriesObjects,
                sourceLayout: input.sourceLayout
            )
        }
    }
}

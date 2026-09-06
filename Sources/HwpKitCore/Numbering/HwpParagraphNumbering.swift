import CoreHwp
import Foundation

/// 문서 순서로 생성한 문단 번호·개요 번호의 표 (#153).
///
/// 조판과 무관한 순수 함수다 — `generate(sections:index:)`가 구역·문단·컨테이너
/// 안 문단을 한 번 훑어 문단마다 `HwpParagraphNumber`를 만들고, 결과는 문단의
/// 위치 경로(`HwpParagraphPath`)로 조회한다. 조판이 같은 문단을 몇 번
/// 재측정·재배치하든(쪽 경계 재시도·다단 재배치) 카운터는 이 한 번의 순회에서만
/// 늘므로 "한 번만 증가"가 구조로 보장된다. `HwpPaginator`는 이 표를 init에서
/// 만들어 두고(`paragraphNumbering`) 라벨 렌더(#154)가 읽는다.
///
/// **정의 해석**은 `HwpNumberingHeadingReference`와 같다 — 개요(문단 머리 종류 1)는
/// 현재 구역 정의의 `numberParaShapeId`, 번호 매기기(종류 2)는 문단 모양의
/// `numberingOrBulletId`. 참조가 0이거나 정의 배열 밖이면 번호를 만들지 않고
/// 카운터도 늘리지 않는다(진단은 조판이 낸다). 글머리표(3)는 대상이 아니다.
/// 현재 구역 정의는 조판(`HwpPaginator.currentSectionDef`)과 같이 문서의 첫 구역
/// 정의에서 시작하므로, 그 정의 문단보다 앞선 문단도 같은 구역으로 센다.
///
/// **카운터 규칙** (`HwpNumberingCounter`; 한글.app 12.30 실측 — 2026-09-06
/// `numbering-sequence` 픽스처 쌍, 같은 세션에서 복사한 라벨 텍스트가 오라클):
/// - **정의마다 목록이 하나다.** 같은 정의의 문단은 사이에 본문·다른 정의의 목록·
///   구역 경계·표가 끼어도 자기 번호를 잇는다. 개요와 번호 매기기는 **종류별로
///   따로** 센다 — 한글은 문단 번호 적용에 새 정의를 만들어 개요 정의와 공유하지
///   않으므로 같은 정의를 공유하는 실물은 없다.
/// - **정의의 첫 문단에서만** 시작 번호 방식을 본다: `HwpNumbering.continuesPreviousList`
///   (시작 번호 0)면 같은 종류에서 직전에 쓰인 정의의 번호를 물려받고(구역
///   나누기가 만든 정의가 앞 구역의 개요 번호를 잇는다 — "앞 구역의 개요 번호에
///   이어서"), 아니면 `startingNumber(forLevel:)`에서 새로 센다. 개요는 구역
///   시작에서 구역 정의의 정의를 활성화하고, 번호 매기기는 구역 시작을 보지
///   않는다. 도움말의 셋째 방식 "이전 번호 목록에 이어"는 대화상자에서 비활성이라
///   실측하지 못했다 — 정의별 목록 규칙이 그 동작을 이미 낸다.
/// - 상위 수준을 매기면 하위 수준은 비워지고, **건너뛴 상위 수준은 시작 번호로
///   매겨진 것으로 친다**(`1.` → 3수준 `1)` → 2수준 `나.`). 비워진 하위 수준을
///   형식이 참조하면 시작 번호를 보인다(대화상자 미리보기 규약, 실물 없음).
///
/// **범위** — 표 셀·글상자·각주·미주·머리말/꼬리말 안 문단도 센다
/// (`HwpPaginator.childParagraphs(of:)`가 여는 컨테이너 전부). 컨테이너 문단은
/// 그것을 품은 본문 문단 **뒤에**, 컨트롤 순서와 자식 문단 순서로 방문하며 같은
/// 종류의 카운터를 쓴다 — 실측: 표를 품은 빈 문단이 `5.`, 셀이 자기 정의로 `9.`·
/// `10.`, 표 뒤 문단이 `6.`. 컨테이너 문단의 개요 정의도 현재 구역의 것이다.
/// 머리말/꼬리말 안 번호 문단은 실물이 없다(같은 규칙으로 센다). 새 번호 지정
/// 컨트롤(`nwno`, 표 144)은 쪽·각주·그림 번호용이라 여기 입력이 아니다.
public struct HwpParagraphNumbering: Sendable, Hashable {
    /// 문단 경로 → 번호. 번호가 없는 문단(머리 종류 0·3, 참조 없음·댕글링)은 없다.
    public let numbers: [HwpParagraphPath: HwpParagraphNumber]
    /// 번호가 붙은 문단의 경로 — 문서 순서.
    public let paths: [HwpParagraphPath]
    /// 순회가 끝까지 가지 못해 **뒤쪽 번호 문단을 버렸는가** — 항목 상한
    /// (`maximumDocumentEntries`)이나 방문 문단 상한(`maximumVisitedParagraphs`)에
    /// 걸렸거나, 생성을 감싼 Task가 취소됐다. 표만 보면 완전한 것과 구별되지
    /// 않으므로 알린다 — 탐색 목록의 `HwpDocumentMetadata.isOutlineTruncated`와 같은
    /// 이유다.
    public let isTruncated: Bool

    /// 한 문서가 가질 수 있는 번호 문단 수의 상한. 항목마다 경로·수준별 번호·
    /// 라벨(최대 `HwpParagraphNumber.textUnitCeiling`)이 문서 수명 내내 상주하므로
    /// 병적 입력이 표만으로 메모리를 고갈시키지 못하게 자른다 — 쪽 상한
    /// (`HwpPaginator.maximumDocumentPages`)이 대신하지 못하는 것은 0-높이 문단이
    /// 쪽을 늘리지 않고도 무한히 이어질 수 있어서다. 실측 최대는 헌법주석의
    /// 1,944개이므로 탐색 목록(`HwpOutlineCollector.maximumDocumentItems`)과 같은
    /// 10배 여유를 둔다. 상한에서 라벨이 512단위씩이어도 약 20MB다.
    public static let maximumDocumentEntries = 20000

    /// 한 문서에서 **걸어 보는** 문단 수(최상위 + 컨테이너 안)의 상한. 항목 상한은
    /// 번호가 붙는 문단에서만 줄어들므로, 번호 없는 문단이 수백만 개인 문서는 그
    /// 상한과 무관하게 순회 자체가 문서를 여는 시간을 삼킨다 — 이 순회는
    /// `HwpPaginator.init`에서 동기로 돌고 조판의 쪽 단위 지연·취소 관찰 밖이다.
    /// 실측 최대는 헌법주석의 14,660개(컨테이너 문단 포함)이므로 약 30배 여유를
    /// 두되, 걷는 비용이 문단당 사전 조회 몇 번이라 상한에서도 1초 안이다.
    public static let maximumVisitedParagraphs = 500_000

    /// 번호가 하나도 없는 표.
    public static let empty = HwpParagraphNumbering(numbers: [:], paths: [], isTruncated: false)

    /// 경로의 문단에 붙은 번호.
    public func number(at path: HwpParagraphPath) -> HwpParagraphNumber? {
        numbers[path]
    }

    /// 최상위 본문 문단의 번호 — `HwpBlockSource.paragraphKey`로 바로 조회한다.
    public func number(for key: HwpParagraphKey) -> HwpParagraphNumber? {
        numbers[HwpParagraphPath(paragraph: key)]
    }

    public subscript(path: HwpParagraphPath) -> HwpParagraphNumber? {
        numbers[path]
    }

    /// 번호가 붙은 문단 수.
    public var count: Int {
        paths.count
    }

    /// 문서 순서의 (경로, 번호) 쌍.
    public var entries: [(path: HwpParagraphPath, number: HwpParagraphNumber)] {
        paths.compactMap { path in numbers[path].map { (path, $0) } }
    }

    /// 구역 배열을 문서 순서로 훑어 표를 만든다. `sections`는 조판이 받는 배열
    /// (`HwpFile.displaySectionArray`)과 같아야 경로가 조판의 위치 열쇠와 맞는다.
    public static func generate(
        sections: [CoreHwp.HwpSection],
        index: HwpIndex
    ) -> HwpParagraphNumbering {
        generate(sections: sections, index: index, maximumEntries: maximumDocumentEntries)
    }

    /// 상한을 재정의하는 생성 — 테스트가 절단 경로를 작은 문서로 재현한다
    /// (`HwpOutlineCollector.maximumItems`와 같은 관례).
    static func generate(
        sections: [CoreHwp.HwpSection],
        index: HwpIndex,
        maximumEntries: Int,
        maximumVisitedParagraphs: Int = maximumVisitedParagraphs
    ) -> HwpParagraphNumbering {
        var walker = Walker(
            sections: sections,
            index: index,
            maximumEntries: maximumEntries,
            maximumVisitedParagraphs: maximumVisitedParagraphs
        )
        walker.walk()
        return HwpParagraphNumbering(
            numbers: walker.numbers, paths: walker.paths, isTruncated: walker.didStop
        )
    }
}

// MARK: - 순회

private extension HwpParagraphNumbering {
    struct Walker {
        let sections: [CoreHwp.HwpSection]
        let index: HwpIndex
        let maximumEntries: Int
        let maximumVisitedParagraphs: Int
        var numbers: [HwpParagraphPath: HwpParagraphNumber] = [:]
        var paths: [HwpParagraphPath] = []
        /// 정의·수준별 형식 분해 메모 — 문단마다 65,535단위 형식을 다시 분해하지 않는다.
        var patterns = HwpNumberingPatternCache()
        /// 지금까지 걸어 본 문단 수(번호 유무와 무관).
        var visitedParagraphs = 0
        /// 순회를 끝까지 가지 못하고 멈췄는가 — 항목 상한·방문 상한·Task 취소.
        /// 멈춘 뒤로는 걷지 않는다 — 세지 않을 문단을 걷는 것은 시간만 쓴다.
        var didStop = false

        /// 취소를 살피는 주기(문단 수). 조판의 `yieldBatchSize`처럼 매 문단이 아니라
        /// 묶음마다 본다 — `Task.isCancelled`는 값싼 읽기지만 문단당 일이 그보다 작다.
        static let cancellationCheckInterval = 256
        /// 현재 구역 정의 — 조판(`HwpPaginator.currentSectionDef`)과 같은 규칙으로
        /// 문서의 첫 구역 정의에서 시작해 구역 정의를 만날 때마다 바뀐다.
        var currentSectionDef: CoreHwp.HwpSectionDef?
        /// 첫 구역 정의는 init에서 이미 적용했으므로 문서에서 처음 만나는 구역
        /// 정의(같은 것)는 건너뛴다 — 안 그러면 그 앞에서 센 개요 번호가 거기서
        /// 비워져 정의 문단이 앞 문단과 같은 번호를 받는다.
        var didSkipFirstSectionDef = false
        var outlineCounter = HwpNumberingCounter()
        var numberingCounter = HwpNumberingCounter()

        init(
            sections: [CoreHwp.HwpSection],
            index: HwpIndex,
            maximumEntries: Int,
            maximumVisitedParagraphs: Int
        ) {
            self.sections = sections
            self.index = index
            self.maximumEntries = maximumEntries
            self.maximumVisitedParagraphs = maximumVisitedParagraphs
            if let first = HwpPaginator.firstSectionDef(for: sections) {
                beginSection(first)
            }
        }

        mutating func walk() {
            for (sectionIndex, section) in sections.enumerated() {
                for (paragraphIndex, paragraph) in section.paragraph.enumerated() {
                    guard !didStop else { return }
                    if let sectionDef = HwpPaginator.sectionDef(in: paragraph) {
                        if didSkipFirstSectionDef {
                            beginSection(sectionDef)
                        } else {
                            didSkipFirstSectionDef = true
                        }
                    }
                    visit(paragraph, path: HwpParagraphPath(
                        sectionIndex: sectionIndex, paragraphIndex: paragraphIndex
                    ))
                }
            }
        }

        /// 구역 시작 — 개요 카운터에 이 구역의 정의를 알린다. 정의를 찾지 못하는
        /// 구역(참조 0·댕글링)은 카운터를 건드리지 않는다.
        mutating func beginSection(_ sectionDef: CoreHwp.HwpSectionDef) {
            currentSectionDef = sectionDef
            let reference = UInt32(sectionDef.numberParaShapeId)
            guard reference > 0, let definition = index.numbering(id: reference - 1) else { return }
            outlineCounter.beginSection(definitionIndex: reference - 1, definition: definition)
        }

        /// 문단 하나에 번호를 매기고 컨테이너 안 문단으로 내려간다. 재귀는 파스
        /// 시점 중첩 한도로 유한하다. 걷는 문단 수가 상한에 닿거나 감싼 Task가
        /// 취소되면 멈춘다 — 이 순회는 `HwpPaginator.init`에서 동기로 돌아 조판의
        /// 문단 단위 취소 관찰 밖이므로 여기서 직접 살핀다(취소된 로드의 표는 어차피
        /// 조판기와 함께 버려진다).
        mutating func visit(_ paragraph: CoreHwp.HwpParagraph, path: HwpParagraphPath) {
            if visitedParagraphs.isMultiple(of: Self.cancellationCheckInterval), Task.isCancelled {
                didStop = true
                return
            }
            guard visitedParagraphs < maximumVisitedParagraphs else {
                didStop = true
                return
            }
            visitedParagraphs += 1
            number(paragraph, path: path)
            for (controlIndex, control) in (paragraph.ctrlHeaderArray ?? []).enumerated() {
                let children = HwpPaginator.childParagraphs(of: control)
                for (childIndex, (child, _)) in children.enumerated() {
                    guard !didStop else { return }
                    visit(child, path: path.appending(
                        controlIndex: controlIndex, childIndex: childIndex
                    ))
                }
            }
        }

        mutating func number(_ paragraph: CoreHwp.HwpParagraph, path: HwpParagraphPath) {
            guard let paraShape = index.paraShape(id: UInt32(paragraph.paraHeader.paraShapeId)),
                  let reference = HwpNumberingHeadingReference.resolve(
                      paraShape: paraShape, sectionDef: currentSectionDef, index: index
                  ),
                  case let .resolved(definitionIndex) = reference.definition,
                  let definition = index.numbering(id: definitionIndex)
            else { return }
            let kind: HwpParagraphNumber.Kind
            let levels: [Int]
            switch reference.kind {
            case .outline:
                kind = .outline
                levels = outlineCounter.number(
                    level: reference.level, definitionIndex: definitionIndex, definition: definition
                )
            case .numbering:
                kind = .numbering
                levels = numberingCounter.number(
                    level: reference.level, definitionIndex: definitionIndex, definition: definition
                )
            }
            // 상한 검사는 항목을 실제로 담는 지점이어야 플래그가 "버린 것이 있다"를
            // 뜻한다 — 번호가 없는 문단은 위 guard에서 이미 돌아갔다.
            guard paths.count < maximumEntries else {
                didStop = true
                return
            }
            let number = HwpParagraphNumber(
                kind: kind,
                definitionIndex: definitionIndex,
                numbers: levels,
                text: HwpNumberingLabelFormatter.text(
                    pattern: patterns.pattern(
                        definitionIndex: definitionIndex, level: levels.count,
                        definition: definition
                    ),
                    definition: definition, level: levels.count, numbers: levels
                )
            )
            numbers[path] = number
            paths.append(path)
        }
    }
}

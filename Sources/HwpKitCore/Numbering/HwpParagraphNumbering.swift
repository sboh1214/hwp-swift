import CoreHwp
import Foundation

/// 문서 순서로 생성한 문단 번호·개요 번호의 표 (#153).
///
/// 조판과 무관한 순수 함수다 — `generate(sections:index:)`가 구역·문단·컨테이너
/// 안 문단을 한 번 훑어 문단마다 `HwpParagraphNumber`를 만들고, 결과는 문단의
/// 위치 경로(`HwpParagraphPath`)로 조회한다. 조판이 같은 문단을 몇 번
/// 재측정·재배치하든(쪽 경계 재시도·다단 재배치) 카운터는 이 한 번의 순회에서만
/// 늘므로 "한 번만 증가"가 구조로 보장된다. `HwpPaginator`는 이 표를 만들어
/// 두고(`paragraphNumbering()`) 라벨 렌더(#154)가 읽는다.
///
/// **정의 해석**은 `HwpNumberingHeadingReference`와 같다 — 개요(문단 머리 종류 1)는
/// 현재 구역 정의의 `numberParaShapeId`, 번호 매기기(종류 2)는 문단 모양의
/// `numberingOrBulletId`. 참조가 0이거나 정의 배열 밖이면 번호를 만들지 않고
/// 카운터도 늘리지 않는다(진단은 조판이 낸다). 글머리표(3)는 대상이 아니다.
///
/// **카운터 규칙** (`HwpNumberingCounter`, 근거는 한컴 도움말 — 문단 번호의
/// "시작 번호 방식"과 개요 번호 모양의 "이전 구역에 이어 / 새 번호로 시작"):
/// - 개요와 번호 매기기는 **카운터를 공유하지 않는다** — 같은 정의를 가리켜도
///   따로 센다. 한글의 두 기능은 별개 대화상자·별개 목록이고, 헌법주석처럼 개요
///   사이에 번호 매기기 목록이 끼어도 장 번호를 잇지 않는다.
/// - 개요는 **구역 시작**에서 구역 정의의 정의를 본다: 시작 번호 방식이 새 번호면
///   1수준부터 시작 번호로, 이어 매기기면 앞 구역의 번호를 잇는다. 헌법주석은
///   41개 구역이 각각 새 번호 정의를 가리켜 조문마다 `I.`부터 세고, 첫 구역만
///   이어 매기기(앞이 없어 1부터)다 — 생성 목차 280개와 일치한다.
/// - 번호 매기기는 **정의가 바뀌는 번호 문단**에서 같은 판정을 한다("새 번호 목록
///   시작"은 한글이 새 정의로 저장한다). 사이에 낀 본문 문단은 목록을 끊지 않는다.
///   도움말의 셋째 방식 "이전 번호 목록에 이어"(다른 정의의 문단을 사이에
///   끼워도 같은 정의의 앞 목록을 잇는다)는 저장 형식을 모르는 상태라 구분하지
///   못한다 — 그런 문서는 이어 매기기로 읽힌다.
/// - 상위 수준을 매기면 하위 수준은 비워지고, 비워진 수준이 형식에 참조되면
///   시작 번호로 보인다.
///
/// **범위** — 표 셀·글상자·각주·미주·머리말/꼬리말 안 문단도 센다. 컨테이너
/// 문단은 그것을 품은 본문 문단 **뒤에**, 컨트롤 순서와 자식 문단 순서
/// (`HwpPaginator.childParagraphs(of:)`)로 방문하며 본문과 **같은 카운터**를
/// 쓴다 — 한글의 "앞 번호 목록에 이어"가 문서 순서로 가장 가까운 번호 문단을
/// 잇는다는 정의를 따른 것이고, 컨테이너 문단의 개요 정의도 현재 구역의 것이다.
/// 실물 대조는 아직이다(noori의 표·글상자 안 개요 문단 4개는 첫 쪽 미리보기에
/// 없다) — 새 번호 지정 컨트롤(`nwno`, 표 144)은 쪽·각주·그림 번호용이라 여기
/// 입력이 아니다.
public struct HwpParagraphNumbering: Sendable, Hashable {
    /// 문단 경로 → 번호. 번호가 없는 문단(머리 종류 0·3, 참조 없음·댕글링)은 없다.
    public let numbers: [HwpParagraphPath: HwpParagraphNumber]
    /// 번호가 붙은 문단의 경로 — 문서 순서.
    public let paths: [HwpParagraphPath]

    /// 번호가 하나도 없는 표.
    public static let empty = HwpParagraphNumbering(numbers: [:], paths: [])

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
        var walker = Walker(sections: sections, index: index)
        walker.walk()
        return HwpParagraphNumbering(numbers: walker.numbers, paths: walker.paths)
    }
}

// MARK: - 순회

private extension HwpParagraphNumbering {
    struct Walker {
        let sections: [CoreHwp.HwpSection]
        let index: HwpIndex
        var numbers: [HwpParagraphPath: HwpParagraphNumber] = [:]
        var paths: [HwpParagraphPath] = []
        /// 현재 구역 정의 — 조판(`HwpPaginator.currentSectionDef`)과 같은 규칙으로
        /// 문서의 첫 구역 정의에서 시작해 구역 정의를 만날 때마다 바뀐다.
        var currentSectionDef: CoreHwp.HwpSectionDef?
        var outlineCounter = HwpNumberingCounter()
        var numberingCounter = HwpNumberingCounter()

        init(sections: [CoreHwp.HwpSection], index: HwpIndex) {
            self.sections = sections
            self.index = index
            currentSectionDef = HwpPaginator.firstSectionDef(for: sections)
        }

        mutating func walk() {
            for (sectionIndex, section) in sections.enumerated() {
                for (paragraphIndex, paragraph) in section.paragraph.enumerated() {
                    if let sectionDef = HwpPaginator.sectionDef(in: paragraph) {
                        beginSection(sectionDef)
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
        /// 시점 중첩 한도로 유한하다.
        mutating func visit(_ paragraph: CoreHwp.HwpParagraph, path: HwpParagraphPath) {
            number(paragraph, path: path)
            for (controlIndex, control) in (paragraph.ctrlHeaderArray ?? []).enumerated() {
                let children = HwpPaginator.childParagraphs(of: control)
                for (childIndex, (child, _)) in children.enumerated() {
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
            let number = HwpParagraphNumber(
                kind: kind,
                level: levels.count,
                definitionIndex: definitionIndex,
                numbers: levels,
                text: HwpNumberingLabelFormatter.text(
                    definition: definition, level: levels.count, numbers: levels
                )
            )
            numbers[path] = number
            paths.append(path)
        }
    }
}
